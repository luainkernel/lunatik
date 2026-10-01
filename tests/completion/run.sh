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
# Usage: sudo bash tests/completion/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="wait mailbox"
STOP="tests/completion/stop"
TOTAL=$(($(echo $TESTS | wc -w) + 1))
SLEEP=1

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/completion/$t" 2>/dev/null
	done
	lunatik stop "$STOP" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

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
check_dmesg || { ktap_totals; exit 1; }

ktap_totals

