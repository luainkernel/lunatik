#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# thread:stop() from a netdevice callback is refused, and accepted once the
# callback returned.
#
# A netdevice callback runs on the task that holds RTNL, and a stop waits for
# the thread's body, which may itself wait on RTNL: registering a netdevice
# notifier, sending a netlink request, joining a multicast group. rtnl.lua is
# spawned, since a thread is started from a thread: its body starts a thread
# whose own body polls shouldstop and schedules, registers a netdevice
# notifier and asks to stop the thread from the replay the registration
# delivers, which is refused with the message the test asserts, then stops it
# from the driver's body, which is accepted, and stops the body's runtime. A
# build without the refusal accepts the stop from the callback and fails the
# assertion rather than hanging, since this body ends on its own and takes no
# RTNL, so the test runs on any build.
#
# Usage: sudo bash tests/thread/rtnl.sh

SCRIPT="tests/thread/rtnl"
REFUSAL="not allowed under RTNL"
TRIES=50

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

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

[ "$(reported "after accepted")" = 1 ] || fail "a thread stop after the callback returned was refused"
ktap_pass "a thread stop once the callback returned is accepted"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

