#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# notifier.netdevice reports the devices of the initial network namespace, the
# one linux.ifindex resolves the name it hands the script in, and not those of
# another namespace, whose names collide with them: the callback is given a
# name only, so a homonym from elsewhere is indistinguishable and resolves onto
# the wrong device.
#
# The path is the per-netns chain of the initial namespace: the replay is
# delivered inside register_netdevice_notifier_net, and a live REGISTER or
# UNREGISTER is delivered under RTNL before the ip command that caused it
# returns, so each assertion reads what the callback already printed. Every
# device the test creates has a homonym on the other side, so what the script
# prints is counted rather than looked for: on the global chain lo is replayed
# twice, once per namespace, and the count is what tells the two registrations
# apart. Live register and unregister cover a dummy device created and deleted
# on both sides.
#
# The assertions read the initial namespace as ground truth, so the suite has to
# run in it, read as PID 1 sharing its namespace; elsewhere the test skips.
#
# Usage: sudo bash tests/notifier/netns_scope.sh

SCRIPT="tests/notifier/netns_scope"
NETNS="netns_scope"
LIVEDEV="nsscope0"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	ip netns del "$NETNS" 2> /dev/null
	ip link del "$LIVEDEV" 2> /dev/null
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 6

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "replay reports lo once, not the lo of another namespace"
	ktap_skip "live register reports a device of the initial namespace"
	ktap_skip "live register does not report a homonym in another namespace"
	ktap_skip "live unregister does not report the device of another namespace"
	ktap_skip "live unregister reports the device of the initial namespace"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "netns scope: $1"
}

command -v ip > /dev/null 2>&1 || skip_all "ip not available"
[ "$(readlink /proc/1/ns/net)" = "$(readlink /proc/self/ns/net)" ] ||
	skip_all "suite runs in a network namespace of its own"
ip link add "$LIVEDEV" type dummy 2> /dev/null || skip_all "cannot create a dummy device"
ip link del "$LIVEDEV"
ip netns add "$NETNS" 2> /dev/null || skip_all "cannot create a network namespace"

mark_dmesg
run_script "$SCRIPT"

[ "$(reported "register lo")" = 1 ] || fail "lo was reported $(reported "register lo") times on the replay"
ktap_pass "replay reports lo once, not the lo of another namespace"

ip link add "$LIVEDEV" type dummy || fail "cannot create $LIVEDEV"
[ "$(reported "register $LIVEDEV")" = 1 ] || fail "$LIVEDEV of the initial namespace was not reported"
ktap_pass "live register reports a device of the initial namespace"

ip -n "$NETNS" link add "$LIVEDEV" type dummy || fail "cannot create $LIVEDEV in $NETNS"
[ "$(reported "register $LIVEDEV")" = 1 ] || fail "$LIVEDEV of $NETNS was reported"
ktap_pass "live register does not report a homonym in another namespace"

ip -n "$NETNS" link del "$LIVEDEV" || fail "cannot delete $LIVEDEV from $NETNS"
[ "$(reported "unregister $LIVEDEV")" = 0 ] || fail "the unregister of $LIVEDEV in $NETNS was reported"
ktap_pass "live unregister does not report the device of another namespace"

ip link del "$LIVEDEV" || fail "cannot delete $LIVEDEV"
[ "$(reported "unregister $LIVEDEV")" = 1 ] || fail "the unregister of $LIVEDEV was not reported"
ktap_pass "live unregister reports the device of the initial namespace"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

