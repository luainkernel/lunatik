#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests socket.unix STREAM: bind/listen/accept on the server side and
# connect/send/receive on the client side, both using the path stored at
# construction time (no explicit path passed to bind() or connect()).
#
# A peer that connects and says nothing must leave the server stoppable. An
# unbounded receive there parks the thread body, and the stop waits for a body
# that never returns: from v6.1 kthread_stop() sets TIF_NOTIFY_SIGNAL
# (a7c01fa93aeb) and the receive raises instead, which the case reads; below
# v6.1 nothing sets that flag and the stop wedges /dev/lunatik for every
# session, so the case skips there. Its peer is a userspace one, since the
# session has to stay open across the stop.
#
# Usage: sudo bash tests/socket/unix/stream.sh

SCRIPT_SERVER="tests/socket/unix/stream_server"
SCRIPT_CLIENT="tests/socket/unix/stream_client"
SOCK="/tmp/lunatik_unix_stream.sock"
MODULE="luasocket"
STOPPABLE="6.1"
SLEEP=1
PEER=""

source "$(dirname "$(readlink -f "$0")")/../../lib.sh"

cleanup() {
	[ -n "$PEER" ] && kill "$PEER" 2>/dev/null
	PEER=""
	lunatik stop "$SCRIPT_SERVER" 2>/dev/null
	lunatik stop "$SCRIPT_CLIENT" 2>/dev/null
	rm -f "$SOCK"
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

[ -e /proc/net/unix ] || {
	echo "# SKIP: no AF_UNIX support"
	ktap_totals
	exit 0
}

mark_dmesg
lunatik spawn "$SCRIPT_SERVER"
sleep $SLEEP

run_script "$SCRIPT_CLIENT"
sleep $SLEEP

lunatik stop "$SCRIPT_SERVER" 2>/dev/null
check_dmesg || { ktap_totals; exit 1; }

found=$(dmesg_since | grep "unix stream: server ok" || true)
[ -z "$found" ] && fail "server did not receive expected message"
ktap_pass "unix.stream server: bind/listen/accept via stored path"

found=$(dmesg_since | grep "unix stream: client ok" || true)
[ -z "$found" ] && fail "client did not complete successfully"
ktap_pass "unix.stream client: connect/send/receive via stored path"

if kernel_atleast "$STOPPABLE" && command -v python3 > /dev/null 2>&1; then
	mark_dmesg
	lunatik stop "$SCRIPT_SERVER" > /dev/null 2>&1
	rm -f "$SOCK"
	spawned=$(lunatik spawn "$SCRIPT_SERVER" 2>&1)
	[ -z "$spawned" ] || { comment "$spawned"; fail "$SCRIPT_SERVER did not spawn"; }
	sleep $SLEEP
	hold_session "$SOCK"
	PEER=$!
	sleep $SLEEP
	lunatik stop "$SCRIPT_SERVER" > /dev/null 2>&1
	sleep $SLEEP
	torn=$(dmesg_since | grep -E "$KTAP_ERRORS" || true)
	kill "$PEER" 2>/dev/null; PEER=""
	[ -z "$torn" ] || { comment "$torn"; fail "the stop tore the server out of its receive"; }
	ktap_pass "unix.stream server: a peer that says nothing does not make the stop an error"
else
	ktap_skip "unix.stream server: a peer that says nothing does not make the stop an error"
fi

ktap_totals

