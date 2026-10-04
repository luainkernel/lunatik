#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# netlink.channel.new and a channel's stop from a netdevice callback are refused,
# and accepted once the callback returned.
#
# A netdevice callback runs on the task that holds RTNL, and registering or
# unregistering a generic netlink family takes cb_lock for writing, which a
# request in flight holds for reading while its handler may wait on RTNL: the
# two tasks then wait on each other. rtnl.lua creates a channel, registers a
# netdevice notifier, and from the replay the registration delivers creates a
# channel and stops the one it holds, both refused with the message the test
# asserts. From the script body it then creates one, multicasts on the held
# channel, which the refused stop left registered, and stops it, all accepted. A
# build without the refusal registers the family under RTNL and hangs only if
# such a request is in flight at that instant, which the test cannot rule out on
# a host it does not own, so it skips unless the loaded luanetlink is the
# installed one and the installed file carries the refusal.
#
# Usage: sudo bash tests/netlink/rtnl.sh

SCRIPT="tests/netlink/rtnl"
MODULE="luanetlink"
REFUSAL="not allowed under RTNL"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 6

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
[ "$(cat /sys/module/$MODULE/srcversion 2> /dev/null)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] &&
	grep -aqF "$REFUSAL" "$(modinfo -n $MODULE 2> /dev/null)" || {
	echo "# SKIP: the loaded $MODULE does not carry the refusal: it may register a family under RTNL"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "netlink rtnl test: $1"
}

mark_dmesg
run_script --context=softirq "$SCRIPT"

[ "$(reported "create $REFUSAL")" = 1 ] || fail "a channel created from a netdevice callback was not refused"
ktap_pass "a channel created from a netdevice callback is refused"

[ "$(reported "after accepted")" = 1 ] || fail "a channel created after the callback returned was refused"
ktap_pass "a channel created once the callback returned is accepted"

[ "$(reported "stop $REFUSAL")" = 1 ] || fail "a channel stopped from a netdevice callback was not refused"
ktap_pass "a channel stopped from a netdevice callback is refused"

[ "$(reported "multicast after accepted")" = 1 ] || fail "a channel whose stop was refused was closed"
ktap_pass "a channel whose stop was refused stays open"

[ "$(reported "stop after accepted")" = 1 ] || fail "a channel stopped after the callback returned was refused"
ktap_pass "a channel stopped once the callback returned is accepted"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

