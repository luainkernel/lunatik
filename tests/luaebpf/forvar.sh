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
#   - a step that is zero at compile time is refused with its message and line
# On a kernel without may_goto (below v6.9) the loop cannot be emitted at all, so the case skips
# the load and asserts the compiler's refusal instead.
#
# Usage: sudo bash tests/luaebpf/forvar.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 4

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

release=$(uname -r | cut -d. -f1,2)
if [ "$(printf '%s\n6.9\n' "$release" | sort -V | head -1)" != "6.9" ]; then
	output=$(luaebpf_compile forvar 2>&1)
	echo "$output" | grep -q "may_goto, which this kernel lacks" \
		|| { comment "$output"; fail "luaebpf: an unbounded loop is not refused without may_goto"; }
	ktap_pass "luaebpf: without may_goto an unbounded loop is refused with its reason"
	ktap_skip "luaebpf: the kernel has no may_goto"
	ktap_skip "luaebpf: the kernel has no may_goto"
	check_dmesg
	ktap_totals
	[ $KTAP_FAIL -eq 0 ]
	exit $?
fi

output=$(luaebpf_compile forvar) || { comment "$output"; fail "luaebpf: forvar.bpf.lua did not compile"; }
log=$(luaebpf_verbose forvar)
[ -e "$LUAEBPF_PINS/varlimit2" ] || { comment "$log"; fail "luaebpf: the loops did not verify"; }
echo "$log" | grep -q "may_goto" \
	|| fail "luaebpf: a loop the compiler cannot bound took no may_goto header"
ktap_pass "luaebpf: an unproven bound takes a may_goto header and verifies"

output=$(luaebpf_differential 4) || { comment "$output"; fail "luaebpf: a loop differs from the interpreter"; }
ktap_pass "luaebpf: every unbounded loop terminates with the interpreter's answer"

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile forvar maygoto) || { comment "$output"; fail "luaebpf: the dropped build failed"; }
output=$(luaebpf_loadall forvar 2>&1)
[ -e "$LUAEBPF_PINS/varlimit2" ] && fail "luaebpf: the loop verified without its may_goto header"
ktap_pass "luaebpf: without the may_goto header the verifier rejects the loop"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

