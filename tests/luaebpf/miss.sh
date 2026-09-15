#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what a compiled program sees when the runtime it calls cannot be dispatched. A program
# returns the callback's PASS where it was reached and its own DROP where the kfunc answered -1,
# so one packet tells the two apart.
#   - with nothing started the call answers nil and the program takes the branch it wrote for it
#   - the nil a call answers is the emitter's own, a zero word: a program that returns it gives
#     what a returned nil gives anywhere else, not the -1 the kfunc handed back
#   - with the runtime started in softirq the same program over the same packet returns the
#     callback's verdict, which is what says the DROP above is the absence and not the object
#   - a runtime started with no execution context is a process-context one, which the kfunc
#     refuses to dispatch. A verdict of -1 from a callback is indistinguishable from no runtime
#     at all -- that is the trampoline's own contract -- so what tells this row from the first is
#     the line the module logs, and the row rests on it. The script it runs attaches no callback,
#     since xdp.attach refuses a process-context runtime before the kfunc ever looks it up
#
# Usage: sudo bash tests/luaebpf/miss.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

SCRIPT=tests/luaebpf/miss
INPROCESS=tests/luaebpf/inprocess
REFUSED="is a process-context runtime, not dispatched"
ABORTED=0
DROP=1
PASS=2
ROWS=4

luaebpf_start $ROWS

gate=$(luaebpf_kfunc luaxdp bpf_luaxdp_run)
if [ -n "$gate" ]; then
	for i in $(seq $ROWS); do ktap_skip "luaebpf: $gate"; done
	ktap_totals
	exit 0
fi

output=$(luaebpf_compile miss) || { comment "$output"; fail "luaebpf: miss.bpf.lua did not compile"; }
output=$(luaebpf_loadall miss) || { comment "$output"; fail "luaebpf: a call into the runtime did not verify"; }

mark_dmesg
got=$(luaebpf_verdict miss)
word=$(luaebpf_verdict nilword)
said=$(dmesg_since | grep -c "$REFUSED")

[ "$got" = "$DROP" ] || fail "luaebpf: a call with no runtime answered '$got', not DROP"
[ "$said" -eq 0 ] || fail "luaebpf: the module refused a runtime none was started under"
ktap_pass "luaebpf: a call whose runtime was never started takes the program's nil branch"

[ "$word" = "$ABORTED" ] || fail "luaebpf: a program returning the nil it was answered gave '$word'"
ktap_pass "luaebpf: the nil a call answers is the emitter's own, not the kfunc's sentinel"

output=$(lunatik run "$SCRIPT" softirq 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the softirq runtime did not start"; }
got=$(luaebpf_verdict miss)
lunatik stop "$SCRIPT" > /dev/null 2>&1

[ "$got" = "$PASS" ] || fail "luaebpf: a call with the runtime up answered '$got', not PASS"
ktap_pass "luaebpf: the same program over the same packet returns the callback's verdict"

mark_dmesg
output=$(lunatik run "$INPROCESS" 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the process-context runtime did not start"; }
got=$(luaebpf_verdict process)
said=$(dmesg_since | grep -c "$REFUSED")
lunatik stop "$INPROCESS" > /dev/null 2>&1

[ "$got" = "$DROP" ] || fail "luaebpf: a process-context runtime answered '$got', not DROP"
[ "$said" -ge 1 ] || fail "luaebpf: the module did not say why it refused to dispatch"
ktap_pass "luaebpf: a process-context runtime is not dispatched, and the module says so"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

