#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for percpu runtimes: `run <script> percpu` registers one
# object holding one runtime per possible CPU id, and the script runs once per
# instance; the script is listed once, by name; stopping it drops every
# instance and lets it run again; `spawn` refuses percpu without creating any
# runtime; and a script that fails on one instance rolls back the ones already
# created, before the failed run returns.
#
# Usage: sudo bash tests/runtime/percpu.sh

SCRIPT="tests/runtime/percpu"
CHECK="tests/runtime/percpu_check"
FAIL_SCRIPT="tests/runtime/percpu_fail"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$CHECK" > /dev/null 2>&1
	lunatik stop "$FAIL_SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 5

mark_dmesg

run_script "$SCRIPT" percpu
run_script "$CHECK"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "one runtime per possible CPU id"

lunatik stop "$CHECK" > /dev/null 2>&1

listed=$(lunatik list)
case "$listed" in
	*"$SCRIPT,"*"$SCRIPT"*) fail "list shows an entry per instance: $listed" ;;
	*"$SCRIPT"*)            ktap_pass "the script is listed once, by name" ;;
	*)                      fail "the script is not listed: $listed" ;;
esac

lunatik stop "$SCRIPT" > /dev/null 2>&1
listed=$(lunatik list)
case "$listed" in
	*"$SCRIPT"*) fail "stop left the script running: $listed" ;;
esac
run_script "$SCRIPT" percpu
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "stop drops every instance and lets the script run again"

output=$(lunatik spawn "$SCRIPT" percpu 2>&1)
echo "$output" | grep -q "spawn does not support percpu" || \
	fail "spawn accepted percpu: $output"
listed=$(lunatik list)
case "$listed" in
	*"$SCRIPT"*) fail "the refused spawn left runtimes behind: $listed" ;;
esac
ktap_pass "spawn refuses percpu without creating runtimes"

# the rollback needs a second instance to fail, so it runs only with >1 possible CPU
if [ "$(nproc --all)" -ge 2 ]; then
	output=$(lunatik run "$FAIL_SCRIPT" percpu 2>&1)
	echo "$output" | grep -q "intentional error on the second instance" || \
		fail "the percpu run did not fail as intended: $output"
	listed=$(lunatik list)
	case "$listed" in
		*"$FAIL_SCRIPT"*) fail "the failed run left the script registered: $listed" ;;
	esac
	mark_dmesg
	run_script "$FAIL_SCRIPT"
	check_dmesg || { ktap_totals; exit 1; }
	lunatik stop "$FAIL_SCRIPT" > /dev/null 2>&1
	ktap_pass "a failing instance rolls back the ones already created"
else
	ktap_skip "a failing instance rolls back the ones already created (needs >1 CPU)"
fi

ktap_totals

