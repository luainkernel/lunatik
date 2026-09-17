#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests a c<n> map key a compiled function builds with getstring.
#   - the maps the program file declares are created and pinned by `bpftool prog loadall ...
#     pinmaps`, and a kernel script opens two of them by their pin paths with the same `c64` and
#     `c16` specs and writes the host name the ClientHello carries
#   - the compiled program reads that name out of the packet and finds the entry: the key it
#     built matches `string.pack("c64", name)` byte for byte, which is what says the buffer was
#     zeroed and the length exact. The `c16` row finds the narrow map's entry, so the width the
#     helper reads is the key spec's and not the buffer's
#   - bytes the map was never keyed with answer nil and take the miss path, and a lookup after a
#     read that failed takes the program's default verdict
#   - an update from the compiled side is what `bpftool map lookup pinned` finds under the padded
#     key
#   - a bytes spec as a map value, a key spec of no bytes at all, a string constant and a number
#     where a bytes key is declared, a string where a number key is, a string bounded wider than
#     the key, a key spec wider than the buffer a string is read into and a string whose read the
#     walk bounded two ways are refused
# The kernel script runs before the programs and stops in the trap, so a failing row leaves the
# next case neither a runtime nor a pin. On a kernel publishing no bpf_xdp_load_bytes the compiler
# refuses the read, and the case skips.
#
# Usage: sudo bash tests/luaebpf/strkey.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

SCRIPT=tests/luaebpf/strkey
WROTE="luaebpf strkey wrote example.com"

# the count the plan declares; ROWS is the rows file here, as in every case whose body writes one
PLAN=14

luaebpf_start "$PLAN"

# a kernel below v5.18 publishes no bpf_xdp_load_bytes, and the compiler refuses the read rather
# than emitting a call to a helper the kernel does not carry
output=$(luaebpf_compile strkey)
if [ $? -ne 0 ]; then
	echo "$output" | grep -q "needs bpf_xdp_load_bytes" \
		|| { comment "$output"; fail "luaebpf: strkey.bpf.lua did not compile"; }
	luaebpf_skipall "$PLAN" "this kernel has no bpf_xdp_load_bytes"
fi
output=$(luaebpf_loadall strkey) || { comment "$output"; fail "luaebpf: the keyed lookups did not verify"; }
ktap_pass "luaebpf: every keyed row verifies, and its map is created and pinned"

ROWS="$LUAEBPF_WORK/rows.txt"

# what the program file's body says the case owes
fact() {
	awk -v k="$1" -v f="$2" -F'\t' '$1 == k && $2 == f {print $3}' "$ROWS"
}

output=$(lunatik run "$SCRIPT" 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the kernel script did not run"; }
wrote=$(dmesg_since | grep -c "$WROTE")
[ "$wrote" -eq 1 ] || fail "luaebpf: the kernel script printed $wrote lines for the name it wrote"
ktap_pass "luaebpf: a kernel script writes the map the program file declared, by its pin path"

got=$(luaebpf_verdict found tls)
[ "$got" = "$(fact expect found)" ] \
	|| fail "luaebpf: the key the program built answered '$got', not the value the script wrote"
ktap_pass "luaebpf: a key getstring built finds what a kernel script wrote under the same name"

got=$(luaebpf_verdict narrow tls)
[ "$got" = "$(fact expect narrow)" ] \
	|| fail "luaebpf: the narrow key answered '$got', so the width read is not the key spec's"
ktap_pass "luaebpf: a c16 key reads the spec's width out of a buffer of sixty-four"

got=$(luaebpf_verdict missing tls)
[ "$got" = "$(fact expect missing)" ] \
	|| fail "luaebpf: bytes the map was never keyed with answered '$got'"
got=$(luaebpf_verdict found truncated)
[ "$got" = "$(fact truncated found)" ] \
	|| fail "luaebpf: a lookup after a failed read answered '$got', not the default verdict"
ktap_pass "luaebpf: a miss and a failed read take the branches the program wrote for them"

got=$(luaebpf_verdict record tls)
[ "$got" = "$(fact expect record)" ] || fail "luaebpf: the update row answered '$got'"
# a key of sixty-four bytes makes bpftool print the value on its own lines rather than beside it
held=$(bpftool map lookup pinned "$LUAEBPF_MAPS/seen" key $(fact key seen) 2>&1 \
	| sed -n '/^value:/,$p' | tail -n +2 | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//; s/ *$//')
[ "$held" = "$(fact value kept)" ] \
	|| fail "luaebpf: the map holds '$held' under the padded key, not '$(fact value kept)'"
ktap_pass "luaebpf: an update from the compiled side lands under the key string.pack writes"

# every row is one compiled function over maps declared beside it, so only the body differs
row() {
	local name="$1" line="$2" message="$3" body="$4"
	{
		echo 'local map = require("bpf.map")'
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo 'local names = map.hash("names", {key = "c64", value = "I4", entries = 8})'
		echo 'local ports = map.hash("ports", {key = "I4", value = "I4", entries = 8})'
		echo 'local shorts = map.hash("shorts", {key = "c16", value = "I4", entries = 8})'
		echo 'local wides = map.hash("wides", {key = "c128", value = "I4", entries = 8})'
		echo ''
		echo 'return xdp.program(function(ctx)'
		echo -e '\tlocal p = ctx:packet()'
		echo "$body"
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$name.bpf.lua:$line: $message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

# a spec refused by the declaration itself, from the file body, so the message carries no line
declaration() {
	local name="$1" message="$2" spec="$3"
	{
		echo 'local map = require("bpf.map")'
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo "local names = map.hash(\"names\", $spec)"
		echo ''
		echo 'return xdp.program(function(ctx)'
		echo -e '\treturn 1'
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message"
	fi
}

declaration bytesvalue "a map value spec packs one value or is a struct codec" \
	'{key = "I4", value = "c64", entries = 8}'
declaration zerokey "a map key is at least one byte" \
	'{key = "c0", value = "I4", entries = 8}'

row constantkey 11 "a map key is a string read from the packet" \
	$'\tlocal v = names["example.com"]\n\tif v then\n\t\treturn v\n\tend\n\treturn 0'
row numberkey 11 "a map key is a string read from the packet" \
	$'\tlocal v = names[7]\n\tif v then\n\t\treturn v\n\tend\n\treturn 0'
row stringnumberkey 12 "a map key is a number here" \
	$'\tlocal s = p:getstring(0, 4)\n\tlocal v = ports[s]\n\tif v then\n\t\treturn v\n\tend\n\treturn 0'
row widekey 16 "a string of up to 32 bytes cannot key a map of 16" \
	$'\tlocal n = p:getbyte(0)\n\tif n > 32 then\n\t\treturn 0\n\tend\n\tlocal s = p:getstring(1, n)\n\tlocal v = shorts[s]\n\tif v then\n\t\treturn v\n\tend\n\treturn 0'
row widespec 16 "a map key of 128 bytes is wider than the 64 a string is read into" \
	$'\tlocal n = p:getbyte(0)\n\tif n > 32 then\n\t\treturn 0\n\tend\n\tlocal s = p:getstring(1, n)\n\tlocal v = wides[s]\n\tif v then\n\t\treturn v\n\tend\n\treturn 0'
row twobounds 20 "a string here was read under more than one bound" \
	$'\tlocal m = p:getbyte(0)\n\tif m > 16 then\n\t\treturn 0\n\tend\n\tlocal n = 8\n\tif n > 16 then\n\t\treturn 0\n\tend\n\tfor i = 1, 4 do\n\t\tlocal v = names[p:getstring(0, n)]\n\t\tn = m\n\tend\n\treturn 0'

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

