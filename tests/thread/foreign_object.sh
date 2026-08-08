#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the thread.run class check: an object of another class
# (a data buffer here) must be refused as the runtime argument, instead of
# having its private data used as a Lua state. The call runs in a spawned
# thread body because thread.run is not allowed during module load.
#
# Usage: sudo bash tests/thread/foreign_object.sh

SCRIPT="tests/thread/foreign_object"
CHECK="tests/thread/foreign_object_check"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$CHECK" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg

output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -n "$output" ] && fail "spawn failed: $output"
sleep 1

run_script "$CHECK"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "thread.run refuses an object of another class"

ktap_totals

