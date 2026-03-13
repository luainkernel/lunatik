#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests socket send/receive with data objects via a UDP loopback socket.
# Verifies valid combinations: data→data, string→data, data→string.
#
# Usage: sudo bash tests/runtime/socket_data.sh

SCRIPT="tests/runtime/socket_data"
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
ktap_pass "socket send/receive with data objects: data→data, string→data, data→string"

ktap_totals

