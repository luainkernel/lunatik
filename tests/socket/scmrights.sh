#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests socket:receiverecord() on an AF_UNIX socket whose peer passes a
# descriptor. A control buffer on that read keeps __scm_recv_common from its
# early exit and reaches scm_detach_fds, which warns on a kernel-space caller
# and returns before __scm_destroy, leaking every file it was handed. The read
# must therefore carry no control buffer where no TLS record type can arrive,
# which is every family but AF_INET and AF_INET6.
#
# The descriptor the peer passes is the write end of a pipe it then closes, so
# the receive holds the last reference to it: the peer's read of the other end
# reports EOF once the receive released it, and blocks when it leaked. That,
# and check_dmesg for the WARNING, are the two verdicts. A userspace peer built
# with gcc is what passes the descriptor, since no kernel binding sends
# SCM_RIGHTS.
#
# Usage: sudo bash tests/socket/scmrights.sh

SCRIPT="tests/socket/scmrights"
MODULE="luasocket"
SOCK="/tmp/lunatik_scmrights.sock"
DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

PEER_BIN="$(mktemp)"
PEER_OUT="$(mktemp)"
PEER_PID=""
cleanup()
{
	kill "$PEER_PID" 2> /dev/null
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	rm -f "$PEER_BIN" "$PEER_OUT" "$SOCK"
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

skip()
{
	echo "# SKIP: $1"
	ktap_skip "scmrights: a receive of passed descriptors reports no record type"
	ktap_skip "scmrights: the descriptors a receive drops are released"
	ktap_totals
	exit 0
}

# the peer prints a marker at each step it reaches; nothing else writes that file
await()
{
	for _ in $(seq 50); do
		grep -q "$1" "$PEER_OUT" 2> /dev/null && return 0
		sleep 0.1
	done
	return 1
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip "$MODULE not loaded"
command -v gcc > /dev/null 2>&1 || skip "gcc unavailable"
gcc -O2 -o "$PEER_BIN" "$DIR/scmrights_peer.c" 2> /dev/null || skip "the peer failed to build"

mark_dmesg
timeout 30 "$PEER_BIN" "$SOCK" > "$PEER_OUT" 2>&1 &
PEER_PID=$!
await listening || fail "the peer did not listen on $SOCK: $(cat "$PEER_OUT")"

run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "socket scmrights: a receive of passed descriptors reports no record type" ||
	fail "scmrights: a receive of passed descriptors reports no record type"
ktap_pass "scmrights: a receive of passed descriptors reports no record type"

await released || fail "scmrights: the descriptors a receive drops are released"
ktap_pass "scmrights: the descriptors a receive drops are released"

ktap_totals

