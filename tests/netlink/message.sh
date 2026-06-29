#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.message: builds a message with attributes and parses it back,
# asserting the round-trip preserves the message type and attribute values.
#
# Usage: sudo bash tests/netlink/message.sh

SCRIPT="tests/netlink/message"
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

dmesg | grep -q "netlink message: round-trip ok" || fail "message round-trip failed"
ktap_pass "message: nlmsghdr/nlattr build and parse round-trip"

ktap_totals

