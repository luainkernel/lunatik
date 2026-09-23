#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# What a socket refuses under RTNL, and what it still does there.
#
# A netdevice callback runs on the task that holds RTNL, and the registration
# replays its first events inside itself, so rtnl.lua probes from the replay a
# notifier.netdevice registration delivers for the devices that already exist,
# loopback always among them. A netlink request runs the kernel's handler on
# the sending task, and rtnetlink's takes RTNL; a receive can continue a dump,
# under the callback mutex rtnetlink sets to RTNL; and an option past
# SOL_SOCKET reaches the protocol, whose multicast memberships take RTNL. Each
# is refused with the message the test asserts: a netlink.rt request, a
# DONTWAIT receive on a NETLINK_ROUTE socket, and IP_TTL, which takes no RTNL
# itself and stands for its level. A SOL_SOCKET option and a UDP send to
# loopback take no RTNL and are accepted there, and the same netlink.rt request
# is accepted once the registration returned.
#
# A tree without the refusal of the request wedges the host rather than failing
# the test: the handler waits on the RTNL its own task holds. So this test runs
# only on a tree that carries it and discriminates by the message it asserts.
# The receive and the option would not wedge one: without the refusal they fail
# with EAGAIN and succeed, and the assertion reads that. The loaded build is not
# always the installed one, so before it registers anything the test looks for
# the notifier's netdevice call, which sets the task the refusal reads, in
# /proc/kallsyms, and skips when the loaded luanotifier does not have it: the
# refusal in luasocket is inline and has no symbol of its own, and a luanotifier
# that sets the task loads only against a core that carries it.
#
# Usage: sudo bash tests/socket/rtnl.sh

SCRIPT="tests/socket/rtnl"
DISPATCH="luanotifier_netdevice_call"
REFUSAL="not allowed under RTNL"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 7

for module in luasocket luanotifier; do
	cat /sys/module/$module/refcnt > /dev/null 2>&1 || {
		echo "# SKIP: $module not loaded"
		ktap_totals
		exit 0
	}
done
grep -Eq " $DISPATCH[[:space:]]\[luanotifier\]$" /proc/kallsyms 2> /dev/null || {
	echo "# SKIP: no $DISPATCH in the loaded luanotifier: nothing sets the task the refusal reads"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "socket rtnl test: $1"
}

mark_dmesg
run_script "$SCRIPT"

[ "$(reported "request $REFUSAL")" = 1 ] || fail "a netlink request from a netdevice callback was not refused"
ktap_pass "a netlink request from a netdevice callback is refused"

[ "$(reported "receive $REFUSAL")" = 1 ] || fail "a netlink receive from a netdevice callback was not refused"
ktap_pass "a receive on a netlink socket from a netdevice callback is refused"

[ "$(reported "protocol option $REFUSAL")" = 1 ] || fail "an IP option from a netdevice callback was not refused"
ktap_pass "an option past SOL_SOCKET from a netdevice callback is refused"

[ "$(reported "socket option accepted")" = 1 ] || fail "a SOL_SOCKET option from a netdevice callback was refused"
ktap_pass "a SOL_SOCKET option from a netdevice callback is accepted"

[ "$(reported "send accepted")" = 1 ] || fail "a UDP send from a netdevice callback was refused"
ktap_pass "a UDP send from a netdevice callback is accepted"

[ "$(reported "after accepted")" = 1 ] || fail "a netlink request after the callback returned was refused"
ktap_pass "a netlink request once the callback returned is accepted"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

