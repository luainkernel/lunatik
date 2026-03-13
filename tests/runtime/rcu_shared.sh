#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test: rcu.table() objects must be clonable so they can be stored
# in lunatik._ENV and retrieved by another runtime.
#
# Usage: sudo bash tests/runtime/rcu_shared.sh

SCRIPT="tests/runtime/rcu_shared"
MODULE="luarcu"

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

lunatik run "$SCRIPT"

check_dmesg || exit 1
ktap_pass "rcu.table() stored in _ENV and retrieved by another runtime"

ktap_totals

