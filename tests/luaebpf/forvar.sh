#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the numeric for whose bounds the compiler cannot prove.
#   - a limit, a step and an initial value the program computes: the loop takes a may_goto
#     header, verifies, and terminates with the interpreter's answer. The verifier's own log is
#     what shows the header, since the kernel rewrites it into a loop counter on the way in
#   - a step that is zero at run time takes the default verdict, which the interpreter raises on
#   - with LUAEBPF_DROP=maygoto the header is gone and the verifier rejects the loop, which is
#     what proves the header is emitted
#   - a step a called function gets at run time takes the default verdict too, through the flag
#     the callee raises in its caller's frame
#   - a step that is zero at compile time is refused with its message and line
#   - with LUAEBPF_PROBE offering the compiler no loop form the loop cannot be emitted at all, and
#     is refused with the reason: that row runs on every kernel, where the kernel's own answer
#     would only run it below v6.9
# On a kernel the compiler says has no may_goto the load rows skip, and what says so is the
# compiler's own refusal rather than the release the kernel reports.
#
# Usage: sudo bash tests/luaebpf/forvar.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 5

cat > "$LUAEBPF_WORK/zerostep.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")

return xdp.program(function(ctx)
	local s = 0
	for i = 1, 10, 0 do
		s = s + i
	end
	return s
end)
LUA
output=$(luaebpf_refuses zerostep "zerostep.bpf.lua:5: 'for' step is zero") \
	|| { comment "$output"; fail "luaebpf: a zero step is not refused"; }
ktap_pass "luaebpf: a 'for' whose step is zero at compile time is refused with its line"

output=$(luaebpf_compile forvar "" loadbytes 2>&1)
echo "$output" | grep -q "which this kernel lacks" \
	|| { comment "$output"; fail "luaebpf: an unbounded loop is not refused without may_goto"; }
ktap_pass "luaebpf: with no loop form offered an unbounded loop is refused with its reason"

output=$(luaebpf_compile forvar)
if [ $? -ne 0 ]; then
	echo "$output" | grep -q "which this kernel lacks" \
		|| { comment "$output"; fail "luaebpf: forvar.bpf.lua did not compile"; }
	for i in $(seq 3); do ktap_skip "luaebpf: the compiler says this kernel has no may_goto"; done
	check_dmesg
	ktap_totals
	[ $KTAP_FAIL -eq 0 ]
	exit $?
fi
log=$(luaebpf_verbose forvar)
[ -e "$LUAEBPF_PINS/varlimit2" ] || { comment "$log"; fail "luaebpf: the loops did not verify"; }
echo "$log" | grep -q "may_goto" \
	|| fail "luaebpf: a loop the compiler cannot bound took no may_goto header"
ktap_pass "luaebpf: an unproven bound takes a may_goto header and verifies"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a loop differs from the interpreter"; }
ktap_pass "luaebpf: every unbounded loop terminates with the interpreter's answer"

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile forvar maygoto) || { comment "$output"; fail "luaebpf: the dropped build failed"; }
output=$(luaebpf_loadall forvar 2>&1)
[ -e "$LUAEBPF_PINS/varlimit2" ] && fail "luaebpf: the loop verified without its may_goto header"
ktap_pass "luaebpf: without the may_goto header the verifier rejects the loop"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

