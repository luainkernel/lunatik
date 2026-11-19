#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the numeric for whose bounds the compiler cannot prove.
#   - a limit, a step and an initial value the program computes: the loop counts its passes with the
#     kernel's iterator, verifies on every kernel, carries a may_goto header on one that has it
#     (v6.9 and later), and terminates with the interpreter's answer. The verifier's own log is what
#     shows the calls and the header, since the kernel rewrites the header into a loop counter on
#     the way in
#   - each way out of such a loop, a break, a return, a stop where Lua raises and a goto out of two
#     loops, alone and from an inner loop, and a stop in a function called from inside one: each
#     destroys the iterator of every loop it leaves, or the verifier refuses the program; a goto to
#     the loop's step leaves none. A break at a value of i the verifier knows and never meets is
#     among them, which a loop carrying i from pass to pass makes the verifier walk without end
#   - a step that is zero at run time, which the interpreter raises on, returns XDP_ABORTED
#   - a loop of more passes than the iterator counts, of a count past the int it takes, one whose
#     low 32 bits would count none after the first among them, returns XDP_ABORTED before its first
#     pass and keeps nothing, in the program and in a function it calls, which the interpreter,
#     making every pass, never gives, so the case asserts it on its own rather than against the oracle
#   - two loops the iterator counts whole, one in the other, whose passes outrun the budget the kernel
#     gives the may_goto of one call, counted or timed, return XDP_ABORTED and keep nothing too; the
#     program is run only on a kernel that has may_goto, since nothing bounds its passes on another
#   - a step a called function gets at run time returns XDP_ABORTED too, through the flag the
#     callee raises in its caller's frame, and the row adds one past the call, so a caller that went
#     on past the flag keeps 1 and returns its default, not XDP_ABORTED
#   - one run of a zero step, in the program and in a called function, and of a division by zero in
#     a loop, in the object loaded again, whose rate limit starts anew, writes into the trace ring at
#     its file and line, once and alone, "'for' step is zero" and "attempt to divide by zero", the
#     callee's line for the callee; one run of each loop past what the iterator counts, and past the
#     may_goto budget where the kernel has it, writes "'for' outruns the budget the kernel gives it"
#     at the line of its 'for', which the interpreter, making every pass, never raises
#   - a step that is zero at compile time is refused with its message and line
#
# Usage: sudo bash tests/luaebpf/forvar.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 6

STEP="'for' step is zero"           # forprep, lua/lvm.c
DIVIDE="attempt to divide by zero" # luaV_idiv
BUDGET="'for' outruns the budget the kernel gives it"

# the loops past the may_goto budget stop at the 'for' whose may_goto spends it, the inner or the outer
drainedlog() {
	local lines inner outer
	lines=$(luaebpf_logged drained)
	inner=$(luaebpf_logline forvar "for _ = #p, #p + LOOPS do" "$BUDGET")
	outer=$(luaebpf_logline forvar "for _ = #p, #p + TURNS do" "$BUDGET")
	[ "$lines" = "$inner" ] || [ "$lines" = "$outer" ] \
		|| echo "drained logged '${lines:-nothing}', not '$BUDGET' at one of its two loops alone"
}

# the line each stop of a loop logs, in the object loaded again
loops() {
	rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
	luaebpf_loadall forvar > /dev/null || { echo "the loops did not verify again"; return; }
	luaebpf_logs varstep3 "$(luaebpf_logline forvar "function makers.varstep" "$STEP")"
	luaebpf_logs calledstep1 "$(luaebpf_logline forvar "for i = 1, 10, step do" "$STEP")"
	luaebpf_logs divides3 "$(luaebpf_logline forvar "function makers.divides" "$DIVIDE")"
	luaebpf_logs spent "$(luaebpf_logline forvar "for _ = 1, #p * SCALE do" "$BUDGET")"
	luaebpf_logs calledspent "$(luaebpf_logline forvar "for _ = 1, #p * SCALE do" "$BUDGET" 2)"
	luaebpf_logs wide "$(luaebpf_logline forvar "for _ = #p, #p + WIDE do" "$BUDGET")"
	luaebpf_logs past "$(luaebpf_logline forvar "for _ = #p, #p + LOOPS + 1 do" "$BUDGET")"
	! luaebpf_maygoto || drainedlog
}

cat > "$LUAEBPF_WORK/zerostep.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

return xdp.program(function(ctx)
	local s = 0
	for i = 1, 10, 0 do
		s = s + i
	end
	return s
end, {default = action.PASS})
LUA
output=$(luaebpf_refuses zerostep "zerostep.bpf.lua:6: 'for' step is zero") \
	|| { comment "$output"; fail "luaebpf: a zero step is not refused"; }
ktap_pass "luaebpf: a 'for' whose step is zero at compile time is refused with its line"

output=$(luaebpf_compile forvar) || { comment "$output"; fail "luaebpf: forvar.bpf.lua did not compile"; }
log=$(luaebpf_verbose forvar)
[ -e "$LUAEBPF_PINS/varlimit2" ] || { comment "$log"; fail "luaebpf: the loops did not verify"; }
echo "$log" | grep -q "bpf_iter_num_new" \
	|| fail "luaebpf: a loop the compiler cannot bound did not count its passes with the iterator"
if luaebpf_maygoto && ! echo "$log" | grep -q "may_goto"; then
	fail "luaebpf: a loop the compiler cannot bound took no may_goto header"
fi
ktap_pass "luaebpf: an unproven bound verifies, counted by the iterator, with may_goto where the kernel has it"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a loop differs from the interpreter"; }
ktap_pass "luaebpf: every unbounded loop, and every way out of one, agrees with the interpreter"

for name in spent calledspent wide past; do
	raw=$(luaebpf_verdict "$name")
	kept=$(luaebpf_kept "$name")
	[ "$raw" = "0" ] && [ "$kept" = absent ] \
		|| fail "luaebpf: $name, past what the iterator counts, returned '$raw' and kept '$kept', not XDP_ABORTED"
done
ktap_pass "luaebpf: a loop past what the iterator counts returns XDP_ABORTED, called or not"

if luaebpf_maygoto; then
	raw=$(luaebpf_verdict drained)
	kept=$(luaebpf_kept drained)
	[ "$raw" = "0" ] && [ "$kept" = absent ] \
		|| fail "luaebpf: drained, past the may_goto budget, returned '$raw' and kept '$kept', not XDP_ABORTED"
	ktap_pass "luaebpf: loops past the budget the kernel gives may_goto return XDP_ABORTED"
else
	ktap_skip "luaebpf: the kernel has no may_goto"
fi

luaebpf_logcase "a zero step, and a loop past the kernel's budget, log their reason at the line of the 'for', once" loops

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

