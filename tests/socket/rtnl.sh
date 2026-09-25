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
# A close runs the socket's release on the calling task, and the release of a
# socket with a multicast membership takes RTNL, an AF_PACKET one for its own
# list, and a NETLINK_GENERIC one a lock a request holds while it waits on
# RTNL; a bind of a generic netlink socket to a group takes that lock too. So
# from the replay a UDP socket with no membership closes, by close() and by a
# <close> local going out of scope, an AF_PACKET and a NETLINK_GENERIC socket
# are refused, the generic netlink group bind is refused and the rtnetlink one
# accepted, and a UDP socket that joined a group before the registration is
# refused, or skipped where no group could be joined; that socket closes once
# the registration returned. An AF_INET6 socket that joined an IPv4 group
# through SOL_IP is refused the same way, its release ending in inet_release,
# and skipped where it could not join.
#
# A tree without the refusal of the request wedges the host rather than failing
# the test: the handler waits on the RTNL its own task holds. So this test runs
# only on a tree that carries it and discriminates by the message it asserts.
# The receive and the option would not wedge one: without the refusal they fail
# with EAGAIN and succeed, and the assertion reads that. The loaded build is not
# always the installed one, so before it registers anything the test looks for
# the notifier's netdevice call, which sets the task the refusal reads, in
# /proc/kallsyms, and skips when the loaded luanotifier does not have it: a
# luanotifier that sets the task loads only against a core that carries it. The
# refusal in luasocket is inline and has no symbol of its own, and a luasocket
# pinned from an older build stays loaded beside a luanotifier that sets the
# task, so the test skips unless the loaded luasocket is the installed one, and
# rtnl.lua sends the request only once the receive, which cannot wedge, was
# refused by the luasocket that is loaded, and the closes and the bind that wait
# on a lock only once the AF_PACKET close, which cannot wedge either, was.
#
# Usage: sudo bash tests/socket/rtnl.sh

SCRIPT="tests/socket/rtnl"
MODULE="luasocket"
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
ktap_plan 12

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
[ "$(cat /sys/module/$MODULE/srcversion)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] || {
	echo "# SKIP: the loaded $MODULE is not the installed one: it may not refuse under RTNL"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "socket rtnl test: $1"
}

mark_dmesg
run_script "$SCRIPT"

[ "$(reported "receive $REFUSAL")" = 1 ] || fail "a netlink receive from a netdevice callback was not refused"
ktap_pass "a receive on a netlink socket from a netdevice callback is refused"

[ "$(reported "request $REFUSAL")" = 1 ] || fail "a netlink request from a netdevice callback was not refused"
ktap_pass "a netlink request from a netdevice callback is refused"

[ "$(reported "protocol option $REFUSAL")" = 1 ] || fail "an IP option from a netdevice callback was not refused"
ktap_pass "an option past SOL_SOCKET from a netdevice callback is refused"

[ "$(reported "socket option accepted")" = 1 ] || fail "a SOL_SOCKET option from a netdevice callback was refused"
ktap_pass "a SOL_SOCKET option from a netdevice callback is accepted"

[ "$(reported "send accepted")" = 1 ] || fail "a UDP send from a netdevice callback was refused"
ktap_pass "a UDP send from a netdevice callback is accepted"

[ "$(reported "close accepted")" = 1 ] || fail "closing a UDP socket with no membership from a netdevice callback was refused"
[ "$(reported "scoped close accepted")" = 1 ] || fail "a <close> UDP socket with no membership going out of scope in a netdevice callback was refused"
[ "$(reported "closed twice accepted")" = 1 ] || fail "a UDP socket closed by name and again by its <close> in a netdevice callback raised"
ktap_pass "a close, a <close> scope, and both on one socket, of a UDP socket with no membership from a netdevice callback are accepted"

[ "$(reported "packet close $REFUSAL")" = 1 ] || fail "closing an AF_PACKET socket from a netdevice callback was not refused"
[ "$(reported "genl close $REFUSAL")" = 1 ] || fail "closing a NETLINK_GENERIC socket from a netdevice callback was not refused"
ktap_pass "a close of an AF_PACKET or a NETLINK_GENERIC socket from a netdevice callback is refused"

[ "$(reported "genl bind $REFUSAL")" = 1 ] || fail "binding a NETLINK_GENERIC socket to a group from a netdevice callback was not refused"
[ "$(reported "route bind accepted")" = 1 ] || fail "binding a NETLINK_ROUTE socket to a group from a netdevice callback was refused"
ktap_pass "a bind of a NETLINK_GENERIC socket to a group from a netdevice callback is refused, and of a NETLINK_ROUTE one accepted"

if [ "$(reported "membership close unavailable")" = 1 ]; then
	ktap_skip "no multicast membership could be joined on this host"
else
	[ "$(reported "membership close $REFUSAL")" = 1 ] || fail "closing a UDP socket with a membership from a netdevice callback was not refused"
	ktap_pass "a close of a UDP socket with a multicast membership from a netdevice callback is refused"
fi

if [ "$(reported "inet6 membership close unavailable")" = 1 ]; then
	ktap_skip "no IPv4 multicast membership could be joined on an AF_INET6 socket on this host"
else
	[ "$(reported "inet6 membership close $REFUSAL")" = 1 ] || fail "closing an AF_INET6 socket with an IPv4 membership from a netdevice callback was not refused"
	[ "$(reported "after inet6 close accepted")" = 1 ] || fail "closing the AF_INET6 socket with an IPv4 membership after the callback returned was refused"
	ktap_pass "a close of an AF_INET6 socket with an IPv4 multicast membership from a netdevice callback is refused, and accepted once it returned"
fi

[ "$(reported "after accepted")" = 1 ] || fail "a netlink request after the callback returned was refused"
[ "$(reported "after close accepted")" = 1 ] || fail "closing the socket with a membership after the callback returned was refused"
ktap_pass "a netlink request, and the close of the socket with a membership, once the callback returned are accepted"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

