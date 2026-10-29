#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the object writer without the translator: the CLI's Lua assembles an XDP program by hand
# with luaebpf.insn, a jump to a label placed past the instruction it skips and a 64-bit immediate
# among its five instructions, writes it with luaebpf.elf and luaebpf.btf once little-endian and
# once big-endian, whatever the host's order, and what reads an object without loading it reads
# each back. For each order:
#   - readelf reads a relocatable eBPF object in that byte order, whose sections are xdp, license,
#     .BTF, .BTF.ext, .symtab and .strtab, in that order
#   - the program is a global FUNC symbol of the xdp section, sized by its six instruction slots
#   - the xdp section holds the instructions as assembled, in that byte order with the register
#     nibbles bpf_insn's bitfields take in it: the jump's offset counts from the instruction after
#     it, and the immediate is split across two slots
#   - the license section reads Dual MIT/GPL
#   - bpftool reads the BTF: the program's FUNC over a FUNC_PROTO taking a long and returning an int
#   - the .BTF.ext header, as Documentation/bpf/btf.rst lays it out, sizes one func_info record and
#     one line_info record per source line, and .BTF carries the file and the line texts they name
# Across the two:
#   - the big-endian .BTF.ext is the little-endian one with every field in the other order
#   - llvm-objdump disassembles the big-endian object for bpfeb to the instructions and relocations
#     it reads in the little-endian one for bpfel; skipped where llvm-objdump is not installed
#
# Usage: sudo bash tests/luaebpf/object.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

CASES=15
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

# a .BTF.ext's hex with every field in the other byte order: the two bytes of the magic, the version
# and flags bytes as they are, and every word past them
btfext_swapped() {
	local hex="$1" out i
	out=${hex:2:2}${hex:0:2}${hex:4:4}
	for ((i = 8; i < ${#hex}; i += 8)); do
		out+=${hex:i+6:2}${hex:i+4:2}${hex:i+2:2}${hex:i:2}
	done
	echo "$out"
}

# the disassembly llvm-objdump reads for one target, without the raw bytes and the file name
disassembly() {
	llvm-objdump --triple="$1" -d -r --no-show-raw-insn "$2" | tail -n +3
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
mark_dmesg

for order in little big; do
	output=$(lua5.5 - "$WORK/$order.o" "$order" 2>&1 <<'LUA'
local insn = require("luaebpf.insn")
local elf  = require("luaebpf.elf")
local btf  = require("luaebpf.btf")

local reg = insn.reg
local bigendian = arg[2] == "big"

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

local object, types = elf.new(bigendian), btf.new(bigendian)
object:section{name = "xdp", type = elf.section.PROGBITS, flags = elf.flags.ALLOC | elf.flags.EXEC,
	data = code:pack(bigendian), align = 8}
object:symbol{name = "prog", section = "xdp", value = 0, size = code:len() * insn.SIZE, bind = elf.bind.GLOBAL,
	type = elf.type.FUNC}
object:section{name = "license", type = elf.section.PROGBITS, flags = elf.flags.ALLOC | elf.flags.WRITE,
	data = "Dual MIT/GPL\0", align = 1}

local texts = {"r0 = 1", "r0 = 0", "r1 = 0x100000002"}
local func = types:func("prog", btf.linkage.GLOBAL, {result = types.int, params = {types.long}})
local file = types:string("object.sh")
local lines, previous = {}, nil
for i, line in ipairs(code:sourcelines()) do
	if line ~= previous then
		table.insert(lines, types:lineinfo((i - 1) * insn.SIZE, file, types:string(texts[line]), line, 1))
		previous = line
	end
end
local ext = types:ext({{name = "xdp", funcs = {types:funcinfo(0, func)}, lines = lines}})
object:section{name = ".BTF", type = elf.section.PROGBITS, flags = 0, data = types:pack(), align = 4}
object:section{name = ".BTF.ext", type = elf.section.PROGBITS, flags = 0, data = ext, align = 4}

local out = assert(io.open(arg[1], "wb"))
assert(out:write(object:pack()))
assert(out:close())
LUA
	) || { comment "$output"; fail "luaebpf: the CLI's Lua did not write the $order-endian object"; }
	[ -s "$WORK/$order.o" ] || fail "luaebpf: the $order-endian object is empty"
done
ktap_pass "luaebpf: the CLI's Lua writes a program assembled by hand in either byte order"

for order in little big; do
	OBJECT="$WORK/$order.o"
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
		|| { comment "$header"; fail "luaebpf: readelf does not read a $order-endian relocatable eBPF object"; }
	sections=$(readelf -S -W "$OBJECT" | sed -n 's/^ *\[ *[1-9][0-9]*\] \([^ ]*\).*/\1/p' | tr '\n' ' ')
	[ "$sections" = "xdp license .BTF .BTF.ext .symtab .strtab " ] \
		|| fail "luaebpf: the $order-endian sections are '$sections'"
	ktap_pass "luaebpf: readelf reads a $order-endian relocatable eBPF object with the sections the writer laid out"

	symbol=$(readelf -s -W "$OBJECT" | awk '$8 == "prog" { print $3, $4, $5, $7 }')
	[ "$symbol" = "48 FUNC GLOBAL 1" ] || fail "luaebpf: the $order-endian program's symbol is '$symbol'"
	ktap_pass "luaebpf: the $order-endian program is a global FUNC of its section, sized by its instructions"

	code=$(section_hex xdp)
	[ "$code" = "${expected// /}" ] || fail "luaebpf: the $order-endian xdp section holds $code"
	ktap_pass "luaebpf: the $order-endian section holds the instructions as assembled, the jump resolved and the immediate split"

	readelf -p license "$OBJECT" | grep -q "Dual MIT/GPL$" \
		|| fail "luaebpf: the $order-endian license section does not read Dual MIT/GPL"
	ktap_pass "luaebpf: the $order-endian license section reads Dual MIT/GPL"

	types=$(bpftool btf dump file "$OBJECT" 2>&1)
	for line in "[1] INT 'int' size=4 bits_offset=0 nr_bits=32 encoding=SIGNED" \
		"[2] INT 'long' size=8 bits_offset=0 nr_bits=64 encoding=SIGNED" \
		"[3] FUNC_PROTO '(anon)' ret_type_id=1 vlen=1" \
		$'\t'"'a1' type_id=2" \
		"[4] FUNC 'prog' type_id=3 linkage=global"; do
		grep -qxF "$line" <<< "$types" || { comment "$types"; fail "luaebpf: bpftool does not read $line in the $order-endian BTF"; }
	done
	ktap_pass "luaebpf: bpftool reads the $order-endian program's FUNC over its FUNC_PROTO"

	# magic and version, hdr_len 32, func_info at 0 for 4 + 8 + 8 bytes, line_info past it for 4 + 8 + 3 * 16
	ext=$(section_hex .BTF.ext)
	[ "${ext:0:48}" = "$exthdr" ] \
		|| fail "luaebpf: the $order-endian .BTF.ext header reads ${ext:0:48}"
	btf=$(section_hex .BTF)
	for text in object.sh "r0 = 1" "r0 = 0" "r1 = 0x100000002"; do
		[[ "$btf" == *"00$(printf '%s' "$text" | od -An -tx1 | tr -d ' \n')00"* ]] \
			|| fail "luaebpf: the $order-endian .BTF does not carry '$text'"
	done
	ktap_pass "luaebpf: the $order-endian .BTF.ext sizes one func_info and a line_info per source line, whose strings .BTF carries"
done

OBJECT="$WORK/little.o"
little=$(section_hex .BTF.ext)
OBJECT="$WORK/big.o"
big=$(section_hex .BTF.ext)
[ "$big" = "$(btfext_swapped "$little")" ] \
	|| { comment "little: $little"; comment "big: $big"; fail "luaebpf: the big-endian .BTF.ext is not the little-endian one swapped"; }
ktap_pass "luaebpf: the big-endian .BTF.ext is the little-endian one with every field swapped"

if ! command -v llvm-objdump >/dev/null; then
	ktap_skip "luaebpf: llvm-objdump is not installed"
else
	little=$(disassembly bpfel "$WORK/little.o")
	big=$(disassembly bpfeb "$WORK/big.o")
	[ -n "$little" ] && [ "$big" = "$little" ] \
		|| { comment "$little"; comment "$big"; fail "luaebpf: llvm-objdump reads the two orders apart"; }
	ktap_pass "luaebpf: llvm-objdump reads the big-endian object for bpfeb as the little-endian one for bpfel"
fi

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

