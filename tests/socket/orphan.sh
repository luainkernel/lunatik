#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that a socket holds its network namespace for as long as the kernel keeps
# the socket, not only for as long as the script does. A TCP socket closed with
# its FIN unanswered stays in the kernel as an orphan, retransmitting the FIN on a
# timer until net.ipv4.tcp_orphan_retries gives up, and a timer that fires after
# the namespace is freed is a use after free. The script opens a listener and a
# client over the loopback of a namespace of the test's own, where an nft rule
# drops every FIN and RST, connects and accepts, then kills the last task in the
# namespace, whose name the test already deleted, and closes the three sockets.
# The two connected ones become orphans, and the veth end the test left in the
# initial namespace, WITNESS, still exists once the script is stopped, since the
# orphans hold the namespace; when the retries run out and the kernel frees them
# the namespace goes and takes WITNESS with it. A kernel that refuses a task's
# namespace with EOPNOTSUPP skips the three cases.
#
# Usage: sudo bash tests/socket/orphan.sh

SCRIPT="tests/socket/orphan"
MODULE="luasocket"
NETNS="lunatik_orphan"
WITNESS="lunatikorphan0"
# retransmissions of the FIN before the kernel frees the orphan: 200ms, then doubling, six seconds in all
ORPHAN_RETRIES=5

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
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
skip() { ktap_skip "$1"; ktap_totals; exit 0; }
command -v nsenter > /dev/null 2>&1 || skip "orphan: nsenter not available"
command -v nft > /dev/null 2>&1 || skip "orphan: nft not available"
netns_up || skip "orphan: cannot create a network namespace"
ip -n "$NETNS" link set lo up 2> /dev/null || skip "orphan: cannot bring loopback up in the namespace"
ip netns exec "$NETNS" sysctl -q -w net.ipv4.tcp_orphan_retries=$ORPHAN_RETRIES 2> /dev/null ||
	skip "orphan: cannot set tcp_orphan_retries in the namespace"
ip netns exec "$NETNS" nft -f - 2> /dev/null <<EOF || skip "orphan: cannot drop packets in the namespace"
table ip lunatik {
	chain output {
		type filter hook output priority filter; policy accept;
		tcp flags & (fin|rst) != 0 drop
	}
}
EOF
ip link add "$WITNESS" type veth peer name "$WITNESS" netns "$NETNS" 2> /dev/null ||
	skip "orphan: cannot create a veth pair"

echo "return {holder = $NSPID}" > "$PIDMOD"
ip netns del "$NETNS"

mark_dmesg
run_script "$SCRIPT"
lunatik stop "$SCRIPT" 2> /dev/null
HELD=$(ip link show "$WITNESS" > /dev/null 2>&1 && echo y)
rm -f "$PIDMOD"
check_dmesg || { ktap_totals; exit 1; }

if dmesg | grep -q "socket orphan: a task's namespace is refused: EOPNOTSUPP"; then
	for _ in 1 2 3; do ktap_skip "a task's namespace: this kernel refuses it"; done
	ktap_totals
	exit 0
fi

dmesg | grep -q "socket orphan: connected and accepted in the namespace" || fail "the script did not connect in the namespace"
ktap_pass "a TCP listener and client connect over the namespace's loopback"

[ "$HELD" = y ] || fail "the namespace went before the kernel freed the orphans"
ktap_pass "the orphans hold the namespace past their close"

for _ in $(seq 1 300); do
	ip link show "$WITNESS" > /dev/null 2>&1 || break
	sleep 0.1
done
ip link show "$WITNESS" > /dev/null 2>&1 && fail "the namespace outlived the orphans"
ktap_pass "the namespace goes once the kernel frees the orphans"

ktap_totals

