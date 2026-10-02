#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# thread:stop() from a netdevice callback is refused, and from under the lock of
# the runtime that holds the notifier, and accepted from another runtime.
#
# A netdevice callback runs on the task that holds RTNL and takes its runtime's
# lock there, and a stop waits for the thread's body, which may itself wait on
# RTNL: registering a netdevice notifier, sending a netlink request, joining a
# multicast group. rtnl.lua is spawned, since a thread is started from a thread:
# its driver starts a thread whose body polls shouldstop and schedules, and
# resumes a second runtime of the same script with it, which registers a
# netdevice notifier and asks to stop the thread from the replay the
# registration delivers, refused under RTNL, and then from its own resumed body,
# refused for the notifier its runtime holds. The driver's runtime holds none,
# so its stop is accepted, and it stops the body's runtime. A build without the
# refusals accepts a stop where they refuse it and fails the assertion rather
# than hanging, since this body ends once stopped and takes no RTNL, so the test
# runs on any build.
#
# Usage: sudo bash tests/thread/rtnl.sh

SCRIPT="tests/thread/rtnl"
REFUSAL="not allowed under RTNL"
HELD="not allowed under the lock of a runtime with a netdevice notifier"
TRIES=50

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

reported()
{
	dmesg_since | grep -cF "thread rtnl test: $1"
}

mark_dmesg
output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$output" ] || fail "$output"
for _ in $(seq $TRIES); do
	[ "$(reported "after")" = 1 ] && break
	sleep 0.1
done
lunatik stop "$SCRIPT" > /dev/null 2>&1

[ "$(reported "stop $REFUSAL")" = 1 ] || fail "a thread stop from a netdevice callback was not refused"
ktap_pass "a thread stop from a netdevice callback is refused"

[ "$(reported "held $HELD")" = 1 ] || fail "a thread stop from under the lock of a runtime with a netdevice notifier was not refused"
ktap_pass "a thread stop from under the lock of a runtime with a netdevice notifier is refused"

[ "$(reported "watch accepted")" = 1 ] || fail "the watcher raised"
[ "$(reported "after accepted")" = 1 ] || fail "a thread stop from a runtime without a netdevice notifier was refused"
ktap_pass "a thread stop from a runtime without a netdevice notifier is accepted"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

