#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the packet bytes a compiled function reads into a buffer of its frame.
#   - a length the program proved by testing the byte it read against the buffer's width, a
#     length that is a constant, a length that is zero or negative at run time, a read past the
#     packet, a negative offset and a read inside a called function, each over the five packets
#     of packets.lua: the interpreter's verdict, or the program's default where it raises. Every
#     row runs under a default no row returns, so a failure path is the verdict the file asked
#     for rather than a number left in R0
#   - the XDP entry's instructions name bpf_xdp_load_bytes with the buffer's eight words zeroed
#     before the call, and the TC one names bpf_skb_load_bytes
#   - a read with no length, one whose length the compiler cannot bound and one bounded above the
#     buffer's width, and an offset or a length that is not a number, are refused with their
#     messages and lines
#   - with LUAEBPF_PROBE naming neither, an XDP read is refused by the helper's name and the
#     kernel's, and a TC one still compiles: bpf_skb_load_bytes is older than every kernel the
#     tree supports and carries no probe
#   - a buffer used as a number, compared with a number, passed to a call, returned, concatenated,
#     '#'-ed or handed to a string function is refused, and eight reads in one function run the
#     frame past the 512 bytes eBPF allows
# On a kernel publishing no bpf_xdp_load_bytes the compiler refuses the read, and the case skips.
#
# Usage: sudo bash tests/luaebpf/getstring.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

ROWS=18

luaebpf_start "$ROWS"

# a kernel below v5.18 publishes no bpf_xdp_load_bytes, and the compiler refuses the read rather
# than emitting a call to a helper the kernel does not carry
output=$(luaebpf_compile getstring)
if [ $? -ne 0 ]; then
	echo "$output" | grep -q "needs bpf_xdp_load_bytes" \
		|| { comment "$output"; fail "luaebpf: getstring.bpf.lua did not compile"; }
	luaebpf_skipall "$ROWS" "this kernel has no bpf_xdp_load_bytes"
fi
output=$(luaebpf_loadall getstring) || { comment "$output"; fail "luaebpf: the reads did not verify"; }
ktap_pass "luaebpf: every getstring row verifies"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a getstring row differs from the interpreter"; }
ktap_pass "luaebpf: every read takes the interpreter's verdict, or the default where it raises"

# the words the buffer takes, zeroed ahead of the call the helper's name is read off
zeroed() {
	bpftool prog dump xlated pinned "$LUAEBPF_PINS/$1" 2>&1 | sed -n "1,/call $2/p" \
		| grep -c 'r10 -[0-9]*) = 0'
}

dump=$(bpftool prog dump xlated pinned "$LUAEBPF_PINS/bounded1" 2>&1)
echo "$dump" | grep -q "call bpf_xdp_load_bytes" \
	|| { comment "$dump"; fail "luaebpf: an XDP read does not call bpf_xdp_load_bytes"; }
words=$(zeroed bounded1 bpf_xdp_load_bytes)
[ "$words" -eq 8 ] || { comment "$dump"; fail "luaebpf: $words words are zeroed before the call, not 8"; }
ktap_pass "luaebpf: an XDP read calls bpf_xdp_load_bytes over a buffer it zeroed first"

dump=$(bpftool prog dump xlated pinned "$LUAEBPF_PINS/sched" 2>&1)
echo "$dump" | grep -q "call bpf_skb_load_bytes" \
	|| { comment "$dump"; fail "luaebpf: a TC read does not call bpf_skb_load_bytes"; }
ktap_pass "luaebpf: a TC read calls bpf_skb_load_bytes"

# every row is one compiled function reading the packet, so the header and the trailer are shared
row() {
	local name="$1" message="$2" body="$3" preamble="${4:-}" module="${5:-xdp}" probe="${6:-}"
	{
		echo "local bpf = require(\"bpf.$module\")"
		echo ''
		echo "$preamble"
		echo "return bpf.program(function(ctx)"
		echo -e "\tlocal p = ctx:packet()"
		echo "$body"
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$message" "$probe")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

row nolength "nolength.bpf.lua:6: 'getstring' takes an offset and a length" \
	$'\tlocal s = p:getstring(0)\n\treturn 1'
row unbounded "unbounded.bpf.lua:7: 'getstring' needs a length the program tested against a constant" \
	$'\tlocal n = p:getbyte(0)\n\tlocal s = p:getstring(1, n)\n\treturn 1'
row notnumbers "notnumbers.bpf.lua:6: 'getstring' takes numbers, not a boolean and a number" \
	$'\tlocal s = p:getstring(true, 4)\n\treturn 1'
row toowide "toowide.bpf.lua:10: 'getstring' reads at most 64 bytes, and this length is bounded at 100" \
	$'\tlocal n = p:getbyte(0)\n\tif n > 100 then\n\t\treturn 0\n\tend\n\tlocal s = p:getstring(1, n)\n\treturn 1'
row noxdphelper \
	"noxdphelper.bpf.lua:6: 'getstring' needs bpf_xdp_load_bytes, which this kernel ($(uname -r)) lacks" \
	$'\tlocal s = p:getstring(0, 4)\n\treturn 1' '' xdp maygoto,iter

cat > "$LUAEBPF_WORK/nolimit.bpf.lua" <<'LUA'
local tc = require("bpf.tc")

return tc.program(function(skb)
	local p = skb:packet()
	local s = p:getstring(0, 4)
	return 0
end)
LUA
output=$(cd "$LUAEBPF_WORK" && LUAEBPF_PROBE=maygoto,iter \
	lunatikc bpf -o "$LUAEBPF_WORK/nolimit.bpf.o" "$LUAEBPF_WORK/nolimit.bpf.lua" 2>&1)
if [ $? -ne 0 ]; then
	comment "$output"
	fail "luaebpf: a TC read was refused though its helper needs no probe"
fi
ktap_pass "luaebpf: a TC read compiles with no probe offering the helper"

row asnumber "asnumber.bpf.lua:7: a string has no value in the kernel here" \
	$'\tlocal s = p:getstring(0, 4)\n\tlocal v = s + 1\n\treturn v'
row asorder "asorder.bpf.lua:7: attempt to compare a string with a number" \
	$'\tlocal s = p:getstring(0, 4)\n\tif s < 3 then\n\t\treturn 0\n\tend\n\treturn 1'
row asargument "asargument.bpf.lua:7: argument #1 is a string, and a compiled call passes numbers and packets" \
	$'\tlocal s = p:getstring(0, 4)\n\tlocal v = width(s)\n\treturn v' \
	'local function width(s) return 4 end'
row returned "returned.bpf.lua:7: a string does not outlive the function that read it" \
	$'\tlocal s = p:getstring(0, 4)\n\treturn s'
row concatenated "concatenated.bpf.lua:7: '..' cannot be applied in a compiled function" \
	$'\tlocal s = p:getstring(0, 4)\n\tlocal t = s .. suffix\n\treturn 1' 'local suffix = "x"'
row measured "measured.bpf.lua:7: '#' cannot be applied in a compiled function" \
	$'\tlocal s = p:getstring(0, 4)\n\tlocal n = #s\n\treturn n'
row stringcall "stringcall.bpf.lua:7: 'len' is not a Lua function this program file declares" \
	$'\tlocal s = p:getstring(0, 4)\n\tlocal n = len(s)\n\treturn n' 'local len = string.len'

{
	echo 'local xdp = require("bpf.xdp")'
	echo ''
	echo 'return xdp.program(function(ctx)'
	echo -e '\tlocal p = ctx:packet()'
	for i in $(seq 8); do echo -e "\tlocal s$i = p:getstring($i, 4)"; done
	echo -e '\treturn 1'
	echo 'end)'
} > "$LUAEBPF_WORK/eight.bpf.lua"
output=$(luaebpf_refuses eight "over the 512 eBPF allows")
if [ $? -ne 0 ]; then
	comment "$output"
	ktap_fail "luaebpf: eight reads in one function"
else
	ktap_pass "luaebpf: eight reads in one function are refused by the frame the object allows"
fi

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

