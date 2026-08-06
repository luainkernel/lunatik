#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for percpu spawn: `spawn <script> percpu` starts one kernel
# thread per possible CPU id, each bound to its own CPU and running its own
# runtime. Every thread records whether it is executing on the CPU its instance
# claims; the check asserts all of them did. Stopping by name drops every
# thread and runtime, and lets the script spawn again.
#
# Usage: sudo bash tests/runtime/percpu_spawn.sh

SCRIPT="tests/runtime/percpu_spawn"
CHECK="tests/runtime/percpu_spawn_check"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$CHECK" > /dev/null 2>&1
}

spawn_percpu()
{
	local output
	output=$(lunatik spawn "$SCRIPT" percpu 2>&1)
	[ -z "$output" ] || fail "spawn percpu failed: $output"
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

mark_dmesg

spawn_percpu
sleep 1
run_script "$CHECK"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$CHECK" > /dev/null 2>&1
ktap_pass "each spawned thread runs on the CPU it is bound to"

lunatik stop "$SCRIPT" > /dev/null 2>&1
listed=$(lunatik list)
case "$listed" in
	*"$SCRIPT"*) fail "stop left the script running: $listed" ;;
esac
spawn_percpu
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "stop drops every thread and lets the script spawn again"

ktap_totals

