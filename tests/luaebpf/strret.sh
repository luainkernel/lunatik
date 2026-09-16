#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the string a compiled function answers through the buffer its caller owns.
#   - a subprogram that reads a name and returns it, the same one frame further, a subprogram
#     that answers a name or nothing tested with `if host then` and with `host == nil`, and a
#     read that fails inside the callee, each over the five packets of packets.lua: the
#     interpreter's verdict, or the program's default where it raises. Every row runs under a
#     default no row returns, so a failure path is the verdict the file asked for rather than a
#     number left in R0
#   - a subprogram taking the three arguments such a function may have of its own, which is the
#     boundary the arity refusal below sits at: the buffer then takes R5, the last register a
#     call has, and the row is the same read reaching the caller through it
#   - a callee whose two returns each carry a buffer of their own, over the same corpus: the ARP
#     frame takes the second return and every other packet the first, and only the second one's
#     read answers the address the caller compares against, so a copy from the wrong buffer is a
#     different verdict
#   - the name a call answered keys the `c64` map the program file declares, with no test where
#     every path of the callee answers a string and after a test where one of them answers
#     nothing: both find the entry seeded under `string.pack("c64", name)`, so the buffer the
#     callee copied out carries the NUL tail as well as the bytes
#   - a program returning a string, a function returning a string on one path and a number on
#     another, a string-returning function taking four arguments of its own, the untested use of
#     what such a call answered, a middle function returning it untested, and two call sites'
#     answers merged into one register are refused with their messages and lines
# On a kernel publishing no bpf_xdp_load_bytes the compiler refuses the read, and the case skips.
#
# Usage: sudo bash tests/luaebpf/strret.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

PLAN=10

luaebpf_start "$PLAN"

# a kernel below v5.18 publishes no bpf_xdp_load_bytes, and the compiler refuses the read rather
# than emitting a call to a helper the kernel does not carry
output=$(luaebpf_compile strret)
if [ $? -ne 0 ]; then
	echo "$output" | grep -q "needs bpf_xdp_load_bytes" \
		|| { comment "$output"; fail "luaebpf: strret.bpf.lua did not compile"; }
	luaebpf_skipall "$PLAN" "this kernel has no bpf_xdp_load_bytes"
fi
output=$(luaebpf_loadall strret) || { comment "$output"; fail "luaebpf: the returned strings did not verify"; }
ktap_pass "luaebpf: every strret row verifies, and its map is created and pinned"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a strret row differs from the interpreter"; }
ktap_pass "luaebpf: every answer takes the interpreter's verdict, or the default where it raises"

ROWS="$LUAEBPF_WORK/rows.txt"

# what the program file's body says the case owes
fact() {
	awk -v k="$1" -v f="$2" -F'\t' '$1 == k && $2 == f {print $3}' "$ROWS"
}

output=$(bpftool map update pinned "$LUAEBPF_MAPS/names" key $(fact key names) \
	value $(fact value names) 2>&1) || { comment "$output"; fail "luaebpf: the map was not seeded"; }

got=$(luaebpf_verdict always tls)
[ "$got" = "$(fact expect seeded)" ] \
	|| fail "luaebpf: a string every path answers keyed the map with '$got'"
ktap_pass "luaebpf: a call that always answers a string keys a map with no test of its own"

got=$(luaebpf_verdict keyed tls)
[ "$got" = "$(fact expect seeded)" ] \
	|| fail "luaebpf: a string narrowed by a test keyed the map with '$got'"
ktap_pass "luaebpf: a call that may answer nothing keys the same map once the program tested it"

# every row is one compiled function over what the file declares beside it, so only the preamble
# and the body differ
row() {
	local name="$1" message="$2" preamble="$3" body="$4"
	{
		echo 'local map = require("bpf.map")'
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo "$preamble"
		echo 'return xdp.program(function(ctx)'
		echo -e '\tlocal p = ctx:packet()'
		echo "$body"
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$name.bpf.lua:$message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

DECLARES='local names = map.hash("names", {key = "c64", value = "I4", entries = 8})'

row program "8: a program returns a verdict, not a string" '' \
	$'\tlocal s = p:getstring(0, 4)\n\treturn s'
row mixed "9: a function that returns a string cannot also return a number" \
	$'local function both(p, at)\n\tif at > 20 then\n\t\treturn 1\n\tend\n\tlocal s = p:getstring(at, 4)\n\treturn s\nend' \
	$'\tlocal v = both(p, 0)\n\treturn 1'
row arity "10: a function that returns a string takes at most 3 arguments, not 4" \
	$'local function wide(p, a, b, c)\n\tlocal s = p:getstring(a + b + c, 4)\n\treturn s\nend' \
	$'\tlocal v = wide(p, 0, 0, 0)\n\treturn 1'
row untested "17: 'host' may be nil here; test it first" \
	"$DECLARES"$'\n\nlocal function host(p, at)\n\tlocal n = p:getbyte(at)\n\tif n < 1 or n > 16 then\n\t\treturn\n\tend\n\tlocal s = p:getstring(at + 1, n)\n\treturn s\nend' \
	$'\tlocal name = host(p, 0)\n\tlocal v = names[name]\n\tif v then\n\t\treturn v\n\tend\n\treturn 1'
row forwarded "15: 'host' may be nil here; test it first" \
	$'local function host(p, at)\n\tlocal n = p:getbyte(at)\n\tif n < 1 or n > 16 then\n\t\treturn\n\tend\n\tlocal s = p:getstring(at + 1, n)\n\treturn s\nend\n\nlocal function forward(p, at)\n\tlocal h = host(p, at)\n\treturn h\nend' \
	$'\tlocal v = forward(p, 0)\n\treturn 1'
row twobuffers "14: a string here was read into more than one buffer" \
	"$DECLARES"$'\n\nlocal function reader(p, at)\n\tlocal s = p:getstring(at, 4)\n\treturn s\nend' \
	$'\tlocal name = reader(p, 0)\n\tfor i = 1, 2 do\n\t\tlocal v = names[name]\n\t\tname = reader(p, 8)\n\tend\n\treturn 1'

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

