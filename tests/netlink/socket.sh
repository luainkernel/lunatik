#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the raw netlink socket: opens a NETLINK_ROUTE socket, sends a
# hand-built RTM_GETLINK dump request and asserts the kernel replies.
#
# Usage: sudo bash tests/netlink/socket.sh

SCRIPT="tests/netlink/socket"
MODULE="luanetlink"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

ktap_header
ktap_plan 1

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink socket: round-trip ok" || fail "no reply from netlink socket"
ktap_pass "socket: send/recv round-trip on a NETLINK_ROUTE socket"

ktap_totals

