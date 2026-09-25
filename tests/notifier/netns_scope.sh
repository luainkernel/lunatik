#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# notifier.netdevice reports the devices of every network namespace, each with
# the inode number of its namespace, which linux.netns() gives for the initial
# one and linux.netns(pid) for a task's: names collide across namespaces, so
# the number is what tells a device from its homonym elsewhere, and what a
# script compares with linux.netns() to keep the devices linux.ifindex resolves.
#
# The path is the global chain, which the devices of every namespace reach: the
# replay is delivered inside register_netdevice_notifier, and a live REGISTER or
# UNREGISTER is delivered under RTNL before the ip command that caused it
# returns, so each assertion reads what the callback already printed. The
# script prints the namespace number with each event, and the test reads the
# initial namespace's from /proc/1/ns/net and the second namespace's from the
# process netns_up keeps there, whose pid the script resolves too, beside pid
# 1's, a reaped pid, which raises ESRCH, and pid 0, which is out of bounds: lo
# is replayed once per namespace, each with its own number, a dummy device
# created and deleted on both sides is reported on register and on unregister
# with the number of the side it was on, and one moved across is unregistered
# with the number of the namespace it leaves and registered with the number of
# the one it joins, the name unchanged.
#
# The assertions read the initial namespace as ground truth, so the suite has to
# run in it, read as PID 1 sharing its namespace; elsewhere the test skips.
#
# Usage: sudo bash tests/notifier/netns_scope.sh

SCRIPT="tests/notifier/netns_scope"
NETNS="netns_scope"
LIVEDEV="nsscope0"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/../netns.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	ip link del "$LIVEDEV" 2> /dev/null
	netns_down
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 10

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "linux.netns names the initial namespace, without a pid and with pid 1, and a task's by its pid"
	ktap_skip "linux.netns raises ESRCH for a pid no task has and refuses one out of bounds"
	ktap_skip "replay reports lo once per namespace, each with its own number"
	ktap_skip "live register reports a device of the initial namespace with its number"
	ktap_skip "live register reports a homonym in another namespace with that namespace's number"
	ktap_skip "live unregister reports the device of another namespace with its number"
	ktap_skip "a move to another namespace is an unregister with the number left and a register with the one joined"
	ktap_skip "a move back to the initial namespace is reported the same way"
	ktap_skip "live unregister reports the device of the initial namespace with its number"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "netns scope: $1"
}

inum()
{
	tr -dc '0-9'
}

command -v ip > /dev/null 2>&1 || skip_all "ip not available"
command -v nsenter > /dev/null 2>&1 || skip_all "nsenter not available"
[ "$(readlink /proc/1/ns/net)" = "$(readlink /proc/self/ns/net)" ] ||
	skip_all "suite runs in a network namespace of its own"
ip link add "$LIVEDEV" type dummy 2> /dev/null || skip_all "cannot create a dummy device"
ip link del "$LIVEDEV"
netns_up || skip_all "cannot create a network namespace"

INIT=$(readlink /proc/1/ns/net | inum)
OTHER=$(readlink "/proc/$NSPID/ns/net" | inum)
[ -n "$INIT" ] && [ -n "$OTHER" ] && [ "$INIT" != "$OTHER" ] || skip_all "cannot read the namespaces' numbers"

true &
REAPED=$!
wait "$REAPED"
echo "return {holder = $NSPID, reaped = $REAPED}" > "$PIDMOD"

mark_dmesg
run_script "$SCRIPT"

[ "$(reported "home $INIT task $INIT holder $OTHER")" = 1 ] || fail "linux.netns(), linux.netns(1) or linux.netns($NSPID) is not its namespace's number"
ktap_pass "linux.netns names the initial namespace, without a pid and with pid 1, and a task's by its pid"

[ "$(reported "reaped pid raises ESRCH, pid 0 is out of bounds")" = 1 ] || fail "a reaped pid or pid 0 did not raise"
ktap_pass "linux.netns raises ESRCH for a pid no task has and refuses one out of bounds"

[ "$(reported "register lo $INIT")" = 1 ] || fail "lo of the initial namespace was reported $(reported "register lo $INIT") times on the replay"
[ "$(reported "register lo $OTHER")" = 1 ] || fail "lo of $NETNS was reported $(reported "register lo $OTHER") times on the replay"
ktap_pass "replay reports lo once per namespace, each with its own number"

ip link add "$LIVEDEV" type dummy || fail "cannot create $LIVEDEV"
[ "$(reported "register $LIVEDEV $INIT")" = 1 ] || fail "$LIVEDEV of the initial namespace was not reported with its number"
ktap_pass "live register reports a device of the initial namespace with its number"

ip -n "$NETNS" link add "$LIVEDEV" type dummy || fail "cannot create $LIVEDEV in $NETNS"
[ "$(reported "register $LIVEDEV $OTHER")" = 1 ] || fail "$LIVEDEV of $NETNS was not reported with its number"
ktap_pass "live register reports a homonym in another namespace with that namespace's number"

ip -n "$NETNS" link del "$LIVEDEV" || fail "cannot delete $LIVEDEV from $NETNS"
[ "$(reported "unregister $LIVEDEV $OTHER")" = 1 ] || fail "the unregister of $LIVEDEV in $NETNS was not reported with its number"
ktap_pass "live unregister reports the device of another namespace with its number"

ip link set "$LIVEDEV" netns "$NETNS" || fail "cannot move $LIVEDEV to $NETNS"
[ "$(reported "unregister $LIVEDEV $INIT")" = 1 ] || fail "the move of $LIVEDEV to $NETNS was not reported as an unregister with the initial namespace's number"
[ "$(reported "register $LIVEDEV $OTHER")" = 2 ] || fail "the move of $LIVEDEV to $NETNS was not reported as a register with $NETNS's number"
ktap_pass "a move to another namespace is an unregister with the number left and a register with the one joined"

ip -n "$NETNS" link set "$LIVEDEV" netns 1 || fail "cannot move $LIVEDEV back from $NETNS"
[ "$(reported "unregister $LIVEDEV $OTHER")" = 2 ] || fail "the move of $LIVEDEV back was not reported as an unregister with $NETNS's number"
[ "$(reported "register $LIVEDEV $INIT")" = 2 ] || fail "the move of $LIVEDEV back was not reported as a register with the initial namespace's number"
ktap_pass "a move back to the initial namespace is reported the same way"

ip link del "$LIVEDEV" || fail "cannot delete $LIVEDEV"
[ "$(reported "unregister $LIVEDEV $INIT")" = 2 ] || fail "the unregister of $LIVEDEV was not reported with its number"
ktap_pass "live unregister reports the device of the initial namespace with its number"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

