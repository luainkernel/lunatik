#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.rt.link_dump(): dumps all network interfaces and verifies
# that the loopback interface (lo, ifindex 1) is present with its name and
# a non-zero MTU.
#
# Usage: sudo bash tests/netlink/link_dump.sh

SCRIPT="tests/netlink/link_dump"
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

dmesg | grep -q "netlink link_dump: lo found" || fail "lo interface not found in link_dump"
ktap_pass "link_dump: lo found with ifindex 1"

dmesg | grep -q "netlink link_dump: mtu ok" || fail "lo MTU not found or is zero"
ktap_pass "link_dump: lo MTU is non-zero"

ktap_totals

