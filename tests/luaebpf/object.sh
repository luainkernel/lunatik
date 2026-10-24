#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the object writer without the translator: the CLI's Lua assembles an XDP program by hand
# with luaebpf.insn, a jump to a label placed past the instruction it skips and a 64-bit immediate
# among its five instructions, writes it with luaebpf.elf and luaebpf.btf, and what reads an object
# without loading it reads it back.
#   - readelf reads a relocatable eBPF object in the host's byte order, whose sections are xdp,
#     license, .BTF, .BTF.ext, .symtab and .strtab, in that order
#   - the program is a global FUNC symbol of the xdp section, sized by its six instruction slots
#   - the xdp section holds the instructions as assembled, in the host's byte order with the
#     register nibbles it lays out: the jump's offset counts from the instruction after it, and the
#     immediate is split across two slots
#   - the license section reads Dual MIT/GPL
#   - bpftool reads the BTF: the program's FUNC over a FUNC_PROTO taking a long and returning an int
#   - the .BTF.ext header, as Documentation/bpf/btf.rst lays it out, sizes one func_info record and
#     one line_info record per source line, and .BTF carries the file and the line texts they name
#
# Usage: sudo bash tests/luaebpf/object.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

CASES=7
WORK=

cleanup() {
	[ -n "$WORK" ] && rm -rf "$WORK"
	return 0
}
trap cleanup EXIT
cleanup

# the hex readelf dumps a section in, without the offsets and the text column
section_hex() {
	readelf -x "$1" "$OBJECT" | awk '$1 ~ /^0x/ { printf "%s%s%s%s", $2, $3, $4, $5 }'
}

ktap_header
ktap_plan $CASES

reason=
command -v readelf >/dev/null || reason="readelf is not installed"
command -v bpftool >/dev/null || reason="bpftool is not installed"
lua5.5 -e 'assert(package.searchpath("luaebpf.insn", package.path))' 2>/dev/null \
	|| reason="luaebpf is not installed; run make and make install"
if [ -n "$reason" ]; then
	for i in $(seq $CASES); do ktap_skip "luaebpf: $reason"; done
	ktap_totals
	exit 0
fi

WORK=$(mktemp -d)
OBJECT="$WORK/object.o"
mark_dmesg

output=$(lua5.5 - "$OBJECT" 2>&1 <<'LUA'
local insn = require("luaebpf.insn")
local elf  = require("luaebpf.elf")
local btf  = require("luaebpf.btf")

local reg = insn.reg

local code = insn.new()
code:source(1)
code:set(reg.R0, 1)
local skip = code:label()
code:jump(skip)
code:source(2)
code:set(reg.R0, 0)
code:place(skip)
code:source(3)
code:set(reg.R1, 0x100000002)
code:exit()

local object, types = elf.new(), btf.new()
object:section{name = "xdp", type = elf.section.PROGBITS, flags = elf.flags.ALLOC | elf.flags.EXEC,
	data = code:pack(), align = 8}
object:symbol{name = "prog", section = "xdp", value = 0, size = code:len() * insn.SIZE, bind = elf.bind.GLOBAL,
	type = elf.type.FUNC}
object:section{name = "license", type = elf.section.PROGBITS, flags = elf.flags.ALLOC | elf.flags.WRITE,
	data = "Dual MIT/GPL\0", align = 1}

local texts = {"r0 = 1", "r0 = 0", "r1 = 0x100000002"}
local func = types:func("prog", 1, btf.linkage.GLOBAL, {result = types.int, param = types.long})
local file = types:string("object.sh")
local lines, previous = {}, nil
for i, line in ipairs(code:sourcelines()) do
	if line ~= previous then
		table.insert(lines, btf.lineinfo((i - 1) * insn.SIZE, file, types:string(texts[line]), line, 1))
		previous = line
	end
end
local ext = types:ext({{name = "xdp", funcs = {btf.funcinfo(0, func)}, lines = lines}})
object:section{name = ".BTF", type = elf.section.PROGBITS, flags = 0, data = types:pack(), align = 4}
object:section{name = ".BTF.ext", type = elf.section.PROGBITS, flags = 0, data = ext, align = 4}

local out = assert(io.open(arg[1], "wb"))
assert(out:write(object:pack()))
assert(out:close())
LUA
) || { comment "$output"; fail "luaebpf: the CLI's Lua did not write the object"; }
[ -s "$OBJECT" ] || fail "luaebpf: the object is empty"
ktap_pass "luaebpf: the CLI's Lua writes a program assembled by hand"

order=$(host_order)
if [ "$order" = little ]; then
	expected="b700000001000000 0500010000000000 b700000000000000 1801000002000000 0000000001000000 9500000000000000"
	exthdr="9feb0100200000000000000014000000140000003c000000"
else
	expected="b700000000000001 0500000100000000 b700000000000000 1810000000000002 0000000000000001 9500000000000000"
	exthdr="eb9f0100000000200000000000000014000000140000003c"
fi

header=$(readelf -h "$OBJECT")
grep -q "Type:.*REL" <<< "$header" && grep -q "Machine:.*Linux BPF" <<< "$header" \
	&& grep -q "Data:.*$order endian" <<< "$header" \
	|| { comment "$header"; fail "luaebpf: readelf does not read a relocatable eBPF object in the host's order"; }
sections=$(readelf -S -W "$OBJECT" | sed -n 's/^ *\[ *[1-9][0-9]*\] \([^ ]*\).*/\1/p' | tr '\n' ' ')
[ "$sections" = "xdp license .BTF .BTF.ext .symtab .strtab " ] \
	|| fail "luaebpf: the sections are '$sections'"
ktap_pass "luaebpf: readelf reads a relocatable eBPF object in the host's order with the sections the writer laid out"

symbol=$(readelf -s -W "$OBJECT" | awk '$8 == "prog" { print $3, $4, $5, $7 }')
[ "$symbol" = "48 FUNC GLOBAL 1" ] || fail "luaebpf: the program's symbol is '$symbol'"
ktap_pass "luaebpf: the program is a global FUNC of its section, sized by its instructions"

code=$(section_hex xdp)
[ "$code" = "${expected// /}" ] || fail "luaebpf: the xdp section holds $code"
ktap_pass "luaebpf: the section holds the instructions as assembled, the jump resolved and the immediate split"

readelf -p license "$OBJECT" | grep -q "Dual MIT/GPL$" || fail "luaebpf: the license section does not read Dual MIT/GPL"
ktap_pass "luaebpf: the license section reads Dual MIT/GPL"

types=$(bpftool btf dump file "$OBJECT" 2>&1)
for line in "[1] INT 'int' size=4 bits_offset=0 nr_bits=32 encoding=SIGNED" \
	"[2] INT 'long' size=8 bits_offset=0 nr_bits=64 encoding=SIGNED" \
	"[3] FUNC_PROTO '(anon)' ret_type_id=1 vlen=1" \
	$'\t'"'a1' type_id=2" \
	"[4] FUNC 'prog' type_id=3 linkage=global"; do
	grep -qxF "$line" <<< "$types" || { comment "$types"; fail "luaebpf: bpftool does not read $line"; }
done
ktap_pass "luaebpf: bpftool reads the program's FUNC over its FUNC_PROTO"

# magic and version, hdr_len 32, func_info at 0 for 4 + 8 + 8 bytes, line_info past it for 4 + 8 + 3 * 16
ext=$(section_hex .BTF.ext)
[ "${ext:0:48}" = "$exthdr" ] \
	|| fail "luaebpf: the .BTF.ext header reads ${ext:0:48}"
btf=$(section_hex .BTF)
for text in object.sh "r0 = 1" "r0 = 0" "r1 = 0x100000002"; do
	[[ "$btf" == *"00$(printf '%s' "$text" | od -An -tx1 | tr -d ' \n')00"* ]] \
		|| fail "luaebpf: .BTF does not carry '$text'"
done
ktap_pass "luaebpf: .BTF.ext sizes one func_info and a line_info per source line, whose strings .BTF carries"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

