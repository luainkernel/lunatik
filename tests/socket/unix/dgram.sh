#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests socket.unix DGRAM: sendto() using the server path stored at
# construction time (no explicit path passed to sendto()).
#
# Usage: sudo bash tests/socket/unix/dgram.sh

SCRIPT_SERVER="tests/socket/unix/dgram_server"
SCRIPT_CLIENT="tests/socket/unix/dgram_client"
SOCK="/tmp/lunatik_unix_dgram.sock"
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

found=$(dmesg_since | grep "unix dgram: server ok" || true)
[ -z "$found" ] && fail "server did not receive expected datagram"
ktap_pass "unix.dgram server: receivefrom with DONTWAIT"

found=$(dmesg_since | grep "unix dgram: client ok" || true)
[ -z "$found" ] && fail "client did not complete successfully"
ktap_pass "unix.dgram client: sendto using stored path (no explicit address)"

ktap_totals

