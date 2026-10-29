#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what a compiled program sees when the kernel Lua runtime it calls is not dispatched: the
# kfunc returns -1, which the call answers as nil. miss.bpf.lua's programs return the callback's
# PASS where it was reached and their own DROP where the call answered nil, so one packet tells the
# two apart, and miss.lua is the runtime, whose callback returns PASS.
#   - with no runtime of that name the call answers nil, and the program takes its nil branch
#   - a program that returns the answer on its nil branch returns its default verdict, as it does
#     any nil, and one that sets the answer to true on its number branch tests the join of the
#     two as false where the call answered nil: the nil branch holds the zero word nil is
#     everywhere else, not the kfunc's -1
#   - with the runtime started in softirq the same program over the same packet returns the
#     callback's verdict, so the DROP above is the absent runtime
#   - 'if not v', 'v ~= nil' and 'v == nil' take the nil arm without the runtime and the number
#     arm with it, as 'if v' does
#   - a runtime started in process context, inprocess.lua, is not dispatched, and the module
#     logs that it refused it, which is what tells this row from the first: the kfunc answers -1
#     either way
# Skips where the kernel publishes no BTF for luaxdp.
#
# Usage: sudo bash tests/luaebpf/miss.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="miss inprocess"
trap cleanup EXIT

SCRIPT=tests/luaebpf/miss
INPROCESS=tests/luaebpf/inprocess
REFUSED="'$INPROCESS' is a process-context runtime, not dispatched"
DROP=1
PASS=2
TX=3
ROWS=5
# the programs testing the answer the three other ways
FORMS="negated unequal equal"

luaebpf_start $ROWS

reason=$(luaebpf_kfunc luaxdp)
if [ -n "$reason" ]; then
	for i in $(seq $ROWS); do ktap_skip "luaebpf: $reason"; done
	ktap_totals
	exit 0
fi

# the verdicts of FORMS' programs, in that order
forms() {
	local form verdicts=
	for form in $FORMS; do
		verdicts="$verdicts $(luaebpf_verdict "$form")"
	done
	echo "${verdicts# }"
}

output=$(luaebpf_compile miss) || { comment "$output"; fail "luaebpf: miss.bpf.lua did not compile"; }
output=$(luaebpf_loadall miss) || { comment "$output"; fail "luaebpf: a call into the runtime did not verify"; }

absent=$(luaebpf_verdict miss)
returned=$(luaebpf_verdict returned)
joined=$(luaebpf_verdict joined)
down=$(forms)
output=$(lunatik run --context=softirq "$SCRIPT" 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the softirq runtime did not start"; }
softirq=$(luaebpf_verdict miss)
up=$(forms)
lunatik stop "$SCRIPT" > /dev/null 2>&1
output=$(lunatik run "$INPROCESS" 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the process-context runtime did not start"; }
process=$(luaebpf_verdict process)
refused=$(dmesg_since | grep -cF "$REFUSED")
lunatik stop "$INPROCESS" > /dev/null 2>&1
rm -rf "$LUAEBPF_PINS"

[ "$absent" = "$DROP" ] || fail "luaebpf: a call with no runtime answered '$absent', not DROP"
ktap_pass "luaebpf: a call whose runtime was never started takes the program's nil branch"

[ "$returned" = "$TX" ] || fail "luaebpf: the nil returned on the nil branch gave '$returned', not the default TX"
[ "$joined" = "$DROP" ] || fail "luaebpf: the nil branch joined with true tested '$joined', not DROP"
ktap_pass "luaebpf: the nil a call answers is the zero word nil is, returned as the default verdict"

[ "$softirq" = "$PASS" ] || fail "luaebpf: a call with the runtime up answered '$softirq', not PASS"
ktap_pass "luaebpf: the same program over the same packet returns the callback's verdict"

[ "$down" = "$DROP $DROP $DROP" ] || fail "luaebpf: $FORMS answered '$down' with no runtime, not DROP each"
[ "$up" = "$PASS $PASS $PASS" ] || fail "luaebpf: $FORMS answered '$up' with the runtime up, not PASS each"
ktap_pass "luaebpf: 'if not v', 'v ~= nil' and 'v == nil' take the nil arm with no runtime and the number arm with it"

[ "$process" = "$DROP" ] || fail "luaebpf: a process-context runtime answered '$process', not DROP"
[ "$refused" -ge 1 ] || fail "luaebpf: the module did not log that it refused the process-context runtime"
ktap_pass "luaebpf: a process-context runtime is not dispatched, and the module says so"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

