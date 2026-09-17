#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the comparison of a string a compiled function read with a string constant.
#   - equal, the constant as a constant of the bytecode and as a value the body computed, a
#     constant that is a prefix of the read, a read that is a prefix of the constant, the empty
#     constant, '~=', and a comparison inside a called function, each over the five packets of
#     packets.lua against the interpreter's own answer
#   - a constant longer than the bound the program proved is never equal, and is settled while
#     compiling: the object carries the comparison where the bound admits the constant and
#     nothing where it does not
#   - the row a comparison of the bytes alone would fail: a read of two bytes more than the host
#     name, whose tail is NUL because the buffer was zeroed, is not equal to the name
#   - two strings compared with each other, a string two reads merged into, and one whose read
#     the walk bounded two ways are refused
# On a kernel publishing no bpf_xdp_load_bytes the compiler refuses the read, and the case skips.
#
# Usage: sudo bash tests/luaebpf/strcmp.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

ROWS=7

luaebpf_start "$ROWS"

# a kernel below v5.18 publishes no bpf_xdp_load_bytes, and the compiler refuses the read rather
# than emitting a call to a helper the kernel does not carry
output=$(luaebpf_compile strcmp)
if [ $? -ne 0 ]; then
	echo "$output" | grep -q "needs bpf_xdp_load_bytes" \
		|| { comment "$output"; fail "luaebpf: strcmp.bpf.lua did not compile"; }
	luaebpf_skipall "$ROWS" "this kernel has no bpf_xdp_load_bytes"
fi
output=$(luaebpf_loadall strcmp) || { comment "$output"; fail "luaebpf: the comparisons did not verify"; }
ktap_pass "luaebpf: every comparison row verifies"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a comparison differs from the interpreter"; }
ktap_pass "luaebpf: every comparison answers what the interpreter answers"

# the first word of the constant, as the program file wrote it and the emitter loads it
word=$(cat "$LUAEBPF_WORK/constant.txt")
carries() {
	bpftool prog dump xlated pinned "$LUAEBPF_PINS/$1" 2>&1 | grep -c "0x$word"
}

[ "$(carries equal4)" -ge 1 ] || fail "luaebpf: the comparison against the constant is not emitted"
[ "$(carries beyond4)" -eq 0 ] \
	|| fail "luaebpf: a constant longer than the proven bound still carries a comparison"
ktap_pass "luaebpf: a constant the bound cannot admit is settled while compiling"

got=$(luaebpf_verdict padded tail)
tail=$(luaebpf_verdict nultail tail)
[ "$got" = "1" ] || fail "luaebpf: the host name read exactly answered '$got', not the equal verdict"
[ "$tail" = "2" ] || fail "luaebpf: the host name read with a NUL tail answered '$tail', not the unequal verdict"
ktap_pass "luaebpf: a read longer than the constant is not equal to it, NUL tail and all"

# every row is one compiled function comparing what it read, so the header and trailer are shared
row() {
	local name="$1" message="$2" body="$3" preamble="${4:-}"
	{
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo "$preamble"
		echo 'return xdp.program(function(ctx)'
		echo -e '\tlocal p = ctx:packet()'
		echo "$body"
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

row twostrings "twostrings.bpf.lua:8: two strings cannot be compared in a compiled function" \
	$'\tlocal s = p:getstring(0, 4)\n\tlocal t = p:getstring(4, 4)\n\tif s == t then\n\t\treturn 1\n\tend\n\treturn 0'
row tworeads "tworeads.bpf.lua:13: a string here was read into more than one buffer" \
	$'\tlocal s\n\tif one < 2 then\n\t\ts = p:getstring(0, 4)\n\telse\n\t\ts = p:getstring(4, 8)\n\tend\n\tif s == name then\n\t\treturn 1\n\tend\n\treturn 0' \
	$'local one = 1\nlocal name = "abcd"'
row twobounds "twobounds.bpf.lua:15: a string here was read under more than one bound" \
	$'\tlocal m = p:getbyte(0)\n\tif m > 16 then\n\t\treturn 1\n\tend\n\tlocal n = 8\n\tif n > 16 then\n\t\treturn 1\n\tend\n\tfor i = 1, 4 do\n\t\tif p:getstring(0, n) == name then\n\t\t\treturn 2\n\t\tend\n\t\tn = m\n\tend\n\treturn 3' \
	'local name = "abcd"'

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

