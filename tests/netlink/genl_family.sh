#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.genl.family(): resolves the always-present generic netlink
# controller family ("nlctrl") and verifies it maps to GENL_ID_CTRL.
#
# Usage: sudo bash tests/netlink/genl_family.sh

SCRIPT="tests/netlink/genl_family"
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

dmesg | grep -q "netlink genl_family: nlctrl resolved" || fail "nlctrl family not resolved"
ktap_pass "genl_family: nlctrl resolves to GENL_ID_CTRL"

ktap_totals

