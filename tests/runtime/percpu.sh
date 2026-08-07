#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for percpu runtimes: `run <script> percpu` registers one
# runtime per possible CPU id as `<script>:<cpu>`, which is what the eBPF
# bindings look up; the script is listed once, by name; stopping it drops every
# instance and lets it run again; a running script is neither run nor spawned
# twice; a script that fails on one instance rolls back the ones already
# created; and the instances are not reachable through a generic stop.
#
# Usage: sudo bash tests/runtime/percpu.sh

SCRIPT="tests/runtime/percpu"
CHECK="tests/runtime/percpu_check"
FAIL_SCRIPT="tests/runtime/percpu_fail"
FAIL_CHECK="tests/runtime/percpu_fail_check"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$CHECK" > /dev/null 2>&1
	lunatik stop "$FAIL_SCRIPT" > /dev/null 2>&1
	lunatik stop "$FAIL_CHECK" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 6

mark_dmesg

run_script "$SCRIPT" percpu
run_script "$CHECK"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "one runtime per possible CPU id"

lunatik stop "$CHECK" > /dev/null 2>&1

listed=$(lunatik list)
case "$listed" in
	*"$SCRIPT:"*) fail "list shows the per-CPU keys: $listed" ;;
	*"$SCRIPT"*)  ktap_pass "the script is listed once, by name" ;;
	*)            fail "the script is not listed: $listed" ;;
esac

lunatik stop "$SCRIPT" > /dev/null 2>&1
listed=$(lunatik list)
case "$listed" in
	*"$SCRIPT"*) fail "stop left the script running: $listed" ;;
esac
run_script "$SCRIPT" percpu
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "stop drops every instance and lets the script run again"

run_script "$SCRIPT" percpu
output=$(lunatik run "$SCRIPT" percpu 2>&1)
echo "$output" | grep -q "is already running" || \
	fail "a second percpu run was accepted: $output"
output=$(lunatik spawn "$SCRIPT" percpu 2>&1)
echo "$output" | grep -q "is already running" || \
	fail "a percpu spawn over a running script was accepted: $output"
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "a running percpu script is not run or spawned twice"

output=$(lunatik run "$FAIL_SCRIPT" percpu 2>&1)
echo "$output" | grep -q "intentional error on the second instance" || \
	fail "the percpu run did not fail as intended: $output"
mark_dmesg
run_script "$FAIL_CHECK"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$FAIL_CHECK" > /dev/null 2>&1
run_script "$FAIL_SCRIPT"
lunatik stop "$FAIL_SCRIPT" > /dev/null 2>&1
ktap_pass "a failing instance rolls back the ones already created"

run_script "$SCRIPT" percpu
lunatik stop "$SCRIPT:0" > /dev/null 2>&1
mark_dmesg
run_script "$CHECK"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$CHECK" > /dev/null 2>&1
lunatik stop "$SCRIPT" > /dev/null 2>&1
run_script "$SCRIPT" percpu
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "instances are not reachable through a generic stop"

ktap_totals

