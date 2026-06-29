#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the AF_NETLINK support in socket: opens an AF_NETLINK socket, binds and
# reads it back (getsockname), and runs an RTM_GETLINK dump round-trip to verify
# send (which attaches the kernel destination) and receive.
#
# Usage: sudo bash tests/netlink/socket.sh

SCRIPT="tests/netlink/socket"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

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

dmesg | grep -q "netlink socket: getsockname ok" || fail "AF_NETLINK bind/getsockname round-trip failed"
ktap_pass "socket: AF_NETLINK bind/getsockname round-trip"

dmesg | grep -q "netlink socket: GETLINK round-trip ok" || fail "AF_NETLINK send/receive round-trip failed"
ktap_pass "socket: AF_NETLINK GETLINK send/receive round-trip"

ktap_totals

