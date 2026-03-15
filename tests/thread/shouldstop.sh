#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for thread.shouldstop() guard against non-kthread context.
#
# Case 1 (run): shouldstop() must return false without crashing.
#   Prior to the fix, kthread_should_stop() dereferenced a NULL pointer for
#   regular processes, panicking the kernel.
#
# Case 2 (spawn): shouldstop() must return true when stop is requested.
#
# Usage: sudo bash tests/thread/shouldstop.sh

SCRIPT_RUN="tests/thread/shouldstop_run"
SCRIPT_SPAWN="tests/thread/shouldstop"
SLEEP=1

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT_RUN"   2>/dev/null
	lunatik stop "$SCRIPT_SPAWN" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

# Case 1: run context — must return false and not crash
mark_dmesg
run_script "$SCRIPT_RUN"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "shouldstop() returns false in run context"

# Case 2: spawn context — must return true when stopped
mark_dmesg
lunatik spawn "$SCRIPT_SPAWN"
sleep $SLEEP
lunatik stop "$SCRIPT_SPAWN"
check_dmesg || { ktap_totals; exit 1; }
found=$(dmesg | tail -n +$((DMESG_LINE+1)) | grep "shouldstop: ok" || true)
[ -z "$found" ] && fail "shouldstop() did not return true in spawn context"
ktap_pass "shouldstop() returns true in spawn context"

ktap_totals

