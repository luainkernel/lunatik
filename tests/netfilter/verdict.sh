#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what a netfilter hook's callback returns. One LOCAL_OUT hook per mark,
# each answering with one case, and one marked ping to 127.0.0.1 per case: a
# callback that returns nothing, or that raises, lets the packet through, as
# ACCEPT does; one that returns a value that is not a number, a verdict spelled as
# a string, a number outside the verdicts, 1 << 32, whose low 32 bits are DROP,
# or STOLEN, REPEAT or STOP, which the kernel would neither free nor pass on, lets
# it through too and logs "invalid verdict", which no other case logs; DROP drops
# it; QUEUE hands it to queue 0, which drops it when nothing listens there, and
# the case skips when something does; and a mark returned beside the verdict is
# stored in the packet, which a later hook matching that mark then drops. Each
# case also reads back the line its callback printed, so a ping that went through
# proves an answer and not a hook that never ran.
#
# Usage: sudo bash tests/netfilter/verdict.sh

SCRIPT="tests/netfilter/verdict"
MODULE="luanetfilter"
PREFIX="netfilter verdict: "
RAISED="${PREFIX}raised"
INVALID="$MODULE: invalid verdict"
QUEUES="/proc/net/netfilter/nfnetlink_queue"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

# ping <mark>: one marked echo request to the loopback
ping_marked() {
	ping -c 1 -W 1 -m "$1" 127.0.0.1 > /dev/null 2>&1
}

# queue 0 has a listener, which takes a queued packet and decides it
listened() {
	awk '$1 == 0 { found = 1 } END { exit !found }' "$QUEUES" 2>/dev/null
}

# expect <mark> <case> <passes|refused|drops> <description>: refused passes and logs INVALID
expect() {
	local mark="$1" case="$2" outcome="$3" desc="$4" status

	mark_dmesg
	ping_marked "$mark"
	status=$?
	dmesg_since | grep -qE "${PREFIX}${case}\$" || fail "$desc: the callback did not run"
	if [ "$outcome" = drops ]; then
		[ $status -ne 0 ] || fail "$desc: the packet went through"
	else
		[ $status -eq 0 ] || fail "$desc: the packet was dropped"
	fi
	if [ "$outcome" = refused ]; then
		dmesg_since | grep -qF "$INVALID" || fail "$desc: the value was not logged"
	else
		dmesg_since | grep -qF "$INVALID" && fail "$desc: the verdict was logged as invalid"
	fi
	check_dmesg || { ktap_totals; exit 1; }
	ktap_pass "$desc"
}

ktap_header
ktap_plan 14

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg

run_script --context=softirq "$SCRIPT"

expect 211 none passes "a callback that returns nothing accepts the packet"
expect 212 boolean refused "a callback that returns a value that is not a number accepts the packet and logs it"
expect 213 string refused "a callback that returns a verdict as a string accepts the packet and logs it"
expect 214 range refused "a callback that returns a number outside the verdicts accepts the packet and logs it"
expect 220 wrap refused "a callback that returns a number whose low 32 bits are DROP accepts the packet and logs it"
expect 221 stolen refused "a callback that returns STOLEN accepts the packet and logs it"
expect 222 repeated refused "a callback that returns REPEAT accepts the packet and logs it"
expect 223 stop refused "a callback that returns STOP accepts the packet and logs it"

expect 215 raise passes "a callback that raises accepts the packet"
dmesg_since | grep -qF "$RAISED" || fail "the raise was not logged"
ktap_pass "a callback that raises logs its error"

expect 216 drop drops "a callback that returns DROP drops the packet"
expect 217 accept passes "a callback that returns ACCEPT accepts the packet"
if listened; then
	ktap_skip "a callback that returns QUEUE queues the packet: queue 0 has a listener"
else
	expect 224 queue drops "a callback that returns QUEUE queues the packet, dropped with no listener"
fi

mark_dmesg
ping_marked 218 && fail "a returned mark was not stored in the packet: it went through"
dmesg_since | grep -qE "${PREFIX}remarked\$" || fail "the hook on the returned mark did not run"
ktap_pass "a mark returned beside the verdict is stored in the packet"

lunatik stop "$SCRIPT" 2>/dev/null
check_dmesg || { ktap_totals; exit 1; }
ktap_totals

