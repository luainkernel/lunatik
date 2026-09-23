#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the pid a netlink session takes: rt.link() without one lists the links
# of the initial network namespace; with the pid of a process in a namespace of
# the test's own it lists that namespace's, where the test put a dummy device
# the initial namespace does not have; the pid of a reaped process raises ESRCH,
# a pid out of range raises and so does a socket the kernel refuses to create
# there. Then the script kills that process, the last task in the namespace,
# whose name the test already deleted, and lists the device again through the
# session it still holds: the socket keeps its namespace alive. Once the script
# has closed its sockets the namespace goes, and with it the veth pair whose
# other end, WITNESS, the test left in the initial namespace: no socket keeps
# its reference past its close, and the one the kernel refused keeps none.
#
# Usage: sudo bash tests/netlink/link_netns.sh

SCRIPT="tests/netlink/link_netns"
MODULE="luasocket"
NETNS="lunatik_link_netns"
DEV="lunatikns0"
WITNESS="lunatikns1"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/../netns.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2> /dev/null
	ip link del "$WITNESS" 2> /dev/null
	netns_down
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
skip() { ktap_skip "$1"; ktap_totals; exit 0; }
command -v nsenter > /dev/null 2>&1 || skip "link_netns: nsenter not available"
netns_up || skip "link_netns: cannot create a network namespace"
ip -n "$NETNS" link add "$DEV" type dummy 2> /dev/null || skip "link_netns: cannot create a dummy device"
ip link add "$WITNESS" type veth peer name "$WITNESS" netns "$NETNS" 2> /dev/null ||
	skip "link_netns: cannot create a veth pair"

true &
REAPED=$!
wait "$REAPED"
echo "return {holder = $NSPID, reaped = $REAPED}" > "$PIDMOD"
ip netns del "$NETNS"

mark_dmesg
run_script "$SCRIPT"
lunatik stop "$SCRIPT" 2> /dev/null
rm -f "$PIDMOD"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink link_netns: initial namespace lists lo, not $DEV" || fail "no pid did not list the initial namespace"
ktap_pass "rt.link() without a pid lists the initial namespace"

if dmesg | grep -q "netlink link_netns: a task's namespace is refused: EOPNOTSUPP"; then
	for _ in $(seq 2 6); do ktap_skip "a task's namespace: this kernel refuses it"; done
	ktap_totals
	exit 0
fi

dmesg | grep -q "netlink link_netns: holder's namespace lists $DEV" || fail "the holder's pid did not reach its namespace"
ktap_pass "rt.link(pid) lists the namespace of that pid"

dmesg | grep -q "netlink link_netns: reaped pid raises ESRCH" || fail "a reaped pid did not raise ESRCH"
ktap_pass "rt.link(pid) raises ESRCH for a pid no task has"

dmesg | grep -q "netlink link_netns: pid out of range and refused socket raise" || fail "a bad pid or socket did not raise"
ktap_pass "socket.new raises on a pid out of range and on a socket refused in the namespace"

dmesg | grep -q "netlink link_netns: $DEV listed after the holder exited" || fail "the session lost its namespace"
ktap_pass "a session keeps its namespace after the last task in it exits"

for _ in $(seq 1 100); do
	ip link show "$WITNESS" > /dev/null 2>&1 || break
	sleep 0.1
done
ip link show "$WITNESS" > /dev/null 2>&1 && fail "the namespace outlived the sockets that held it"
ktap_pass "the namespace goes once the last socket holding it is closed"

ktap_totals

