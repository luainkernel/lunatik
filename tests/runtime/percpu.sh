#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for percpu runtimes: `run <script> percpu` registers one
# runtime per possible CPU id as `<script>:<cpu>`, which is what the eBPF
# bindings look up; the script is listed once, by name; stopping it drops every
# instance and lets it run again; and `spawn` refuses percpu without creating
# any runtime.
#
# Usage: sudo bash tests/runtime/percpu.sh

SCRIPT="tests/runtime/percpu"
CHECK="tests/runtime/percpu_check"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$CHECK" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

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

output=$(lunatik spawn "$SCRIPT" percpu 2>&1)
echo "$output" | grep -q "spawn does not support percpu" || \
	fail "spawn accepted percpu: $output"
listed=$(lunatik list)
case "$listed" in
	*"$SCRIPT"*) fail "the refused spawn left runtimes behind: $listed" ;;
esac
ktap_pass "spawn refuses percpu without creating runtimes"

ktap_totals

