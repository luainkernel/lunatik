#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Verifies that socket send/receive reject wrong-type userdata and non-SINGLE
# data objects with a proper Lua error rather than crashing the kernel.
#
# Usage: sudo bash tests/runtime/socket_data_reject.sh

SCRIPT="tests/runtime/socket_data_reject"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

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
ktap_pass "socket send/receive correctly reject wrong-type and non-SINGLE data"

ktap_totals

