#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.rt.addr_dump(): dumps interface addresses and verifies that
# the loopback address 127.0.0.1/8 is present.
#
# Usage: sudo bash tests/netlink/addr_dump.sh

SCRIPT="tests/netlink/addr_dump"
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

dmesg | grep -q "netlink addr_dump: 127.0.0.1 found" || fail "127.0.0.1 not found in addr_dump"
ktap_pass "addr_dump: 127.0.0.1 present on loopback"

dmesg | grep -q "netlink addr_dump: prefix_len ok" || fail "loopback prefix_len != 8"
ktap_pass "addr_dump: loopback prefix_len == 8"

ktap_totals

