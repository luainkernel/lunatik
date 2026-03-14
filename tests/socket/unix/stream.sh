#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests socket.unix STREAM: bind/listen/accept on the server side and
# connect/send/receive on the client side, both using the path stored at
# construction time (no explicit path passed to bind() or connect()).
#
# Usage: sudo bash tests/socket/unix/stream.sh

SCRIPT_SERVER="tests/socket/unix/stream_server"
SCRIPT_CLIENT="tests/socket/unix/stream_client"
SOCK="/tmp/lunatik_unix_stream.sock"
MODULE="luasocket"
SLEEP=1

source "$(dirname "$(readlink -f "$0")")/../../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT_SERVER" 2>/dev/null
	lunatik stop "$SCRIPT_CLIENT" 2>/dev/null
	rm -f "$SOCK"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
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

found=$(dmesg | tail -n +$((DMESG_LINE+1)) | grep "unix stream: server ok" || true)
[ -z "$found" ] && fail "server did not receive expected message"
ktap_pass "unix.stream server: bind/listen/accept via stored path"

found=$(dmesg | tail -n +$((DMESG_LINE+1)) | grep "unix stream: client ok" || true)
[ -z "$found" ] && fail "client did not complete successfully"
ktap_pass "unix.stream client: connect/send/receive via stored path"

ktap_totals

