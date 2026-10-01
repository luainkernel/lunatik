#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests socket.inet's getsockname() and getpeername(): a TCP listener bound to
# 127.0.0.1 on an ephemeral port answers with that address as a string and the
# port, and a client connected to it answers with the same pair as its peer.
#
# Usage: sudo bash tests/socket/inet.sh

SCRIPT="tests/socket/inet"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
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
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "socket inet: getsockname ok" || fail "getsockname did not answer the bound address and port"
ktap_pass "inet getsockname: a bound socket answers with its address as a string and its port"

dmesg | grep -q "socket inet: getpeername ok" || fail "getpeername did not answer the peer's address and port"
ktap_pass "inet getpeername: a connected socket answers with the peer's address as a string and its port"

ktap_totals

