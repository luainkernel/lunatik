#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs completion regression tests and reports aggregated KTAP results.
#
# wait: completion:wait answers true for a completion signaled before it, with a
# timeout and with timeout 0, and false, alone, when the timeout elapses first.
#
# mailbox: mailbox:receive answers nil, alone, when its wait elapses, timeout 0
# included, and the message a send queued before it; mailbox:send answers false
# when the queue has no room for a message, which the receiver then never sees.
#
# stop: the stop of a spawned thread interrupts its completion:wait, which raises
# ERESTARTSYS. The body bounds its wait, so it ends on its own when no stop comes.
#
# deferred: a hardirq runtime's callback, which runs with IRQs off, completes a
# completion twice, and so does a softirq runtime's, which runs with them on:
# the waiter wakes twice for each, the softirq's at once and the hardirq's within
# a second, and not a third time. A second hardirq callback then completes the
# same completion twice after the worker drained the first two, and wakes the
# waiter twice again, not four times.
#
# drained: a kprobe on luacompletion_drain, armed before the cases, counts one run
# on the kernel worker for each hardirq callback, its two completes merged into
# it: IRQs stay off across the callback, so the irq_work the first raises runs
# after the second. Every other complete wakes in place. A build that completes
# in place with IRQs off wakes the waiters as this one does, and fails here.
#
# Usage: sudo bash tests/completion/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="wait mailbox deferred"
STOP="tests/completion/stop"
DRAINED="lunatik_completion/luacompletion_drain"
TOTAL=$(($(echo $TESTS | wc -w) + 2))
SLEEP=1

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/completion/$t" 2>/dev/null
	done
	lunatik stop "$STOP" 2>/dev/null
	kprobe_remove "$DRAINED"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

kprobe_place "$DRAINED" luacompletion_drain && before=$(kprobe_hits "$DRAINED")

for t in $TESTS; do
	if run_test "tests/completion/$t"; then
		ktap_pass "completion/$t"
	else
		ktap_fail "completion/$t"
	fi
done

mark_dmesg
spawned=$(lunatik spawn "$STOP" 2>&1)
sleep $SLEEP
lunatik stop "$STOP" 2>/dev/null
[ -z "$spawned" ] || comment "$spawned"
if dmesg_since | grep -q "completion stop: ERESTARTSYS"; then
	ktap_pass "completion/stop: a stop interrupts the wait, which raises ERESTARTSYS"
else
	comment "$(dmesg_since | grep "completion stop:")"
	ktap_fail "completion/stop: a stop interrupts the wait, which raises ERESTARTSYS"
fi

if ! grep -qw luacompletion_drain /proc/kallsyms; then
	ktap_fail "completion/drained: the loaded luacompletion carries no luacompletion_drain"
elif [ -z "${before:-}" ]; then
	ktap_skip "completion/drained: couldn't place a kprobe on luacompletion_drain"
else
	drains=$(( $(kprobe_hits "$DRAINED") - before ))
	if [ "$drains" -eq 2 ]; then
		ktap_pass "completion/drained: the completes with IRQs off ran on a kernel worker, once per callback"
	else
		ktap_fail "completion/drained: $drains runs on a kernel worker, not the two the hardirq callbacks queued"
	fi
fi
check_dmesg || { ktap_totals; exit 1; }

ktap_totals

