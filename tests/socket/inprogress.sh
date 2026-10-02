#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what a TCP socket answers when a send timeout (SO_SNDTIMEO) ends its wait
# for a handshake that does not complete. The script connects over the loopback
# of a network namespace of the test's own, where an nft rule drops every segment
# to the port, so the SYN never draws an answer. A connect bounded by the timeout
# answers nil and "EINPROGRESS" once the timeout ends its wait, as a nonblocking
# one does at once (connect.sh), and a send on the same socket, which waits for
# the handshake before it queues anything, answers false once the timeout ends
# that wait. A kernel that refuses a task's namespace with EOPNOTSUPP skips both
# cases. The shell has to run in the initial pid namespace, the only one where the
# pid socket.new resolves is the one the test hands it, and the test skips
# elsewhere.
#
# Usage: sudo bash tests/socket/inprogress.sh

SCRIPT="tests/socket/inprogress"
MODULE="luasocket"
NETNS="lunatik_inprogress"
PORT=6924

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/../netns.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2> /dev/null
	netns_down
}
trap cleanup EXIT
cleanup

expect() { # expect <line> <description>
	dmesg_since | grep -q "socket inprogress: $1" || fail "$2"
	ktap_pass "$2"
}

ktap_header
ktap_plan 2

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
skip() { ktap_skip "$1"; ktap_totals; exit 0; }
command -v nsenter > /dev/null 2>&1 || skip "inprogress: nsenter not available"
initpidns || skip "inprogress: suite runs in a pid namespace of its own"
command -v nft > /dev/null 2>&1 || skip "inprogress: nft not available"
netns_up || skip "inprogress: cannot create a network namespace"
ip -n "$NETNS" link set lo up 2> /dev/null || skip "inprogress: cannot bring loopback up in the namespace"
ip netns exec "$NETNS" nft -f - 2> /dev/null <<EOF || skip "inprogress: cannot drop packets in the namespace"
table ip lunatik {
	chain input {
		type filter hook input priority filter; policy accept;
		tcp dport $PORT drop
	}
}
EOF
echo "return {holder = $NSPID}" > "$PIDMOD"

mark_dmesg
run_script "$SCRIPT"
cleanup
check_dmesg || { ktap_totals; exit 1; }

if dmesg_since | grep -q "socket inprogress: a task's namespace is refused: EOPNOTSUPP"; then
	for _ in 1 2; do ktap_skip "a task's namespace: this kernel refuses it"; done
	ktap_totals
	exit 0
fi

expect "a timed connect answers nil and EINPROGRESS" "socket inprogress: a connect a send timeout ends answers nil and EINPROGRESS"
expect "a timed send while connecting answers false" "socket inprogress: a send a send timeout ends before the handshake answers false"

ktap_totals

