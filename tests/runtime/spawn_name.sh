#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the name runner.spawn gives its thread: the last two components of the
# script's path, whatever characters they carry. A script whose name has an
# underscore must not name its thread after the text past it, which is what an
# operator would then find in ps and in the kernel log. The spawned script's name
# fits in the 15 characters a task's comm holds, so the check reads it whole; its
# body returns at once, the thread object keeping the task readable.
#
# Usage: sudo bash tests/runtime/spawn_name.sh

SCRIPT="tests/runtime/my_body"
CHECK="tests/runtime/spawn_name"

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
run_script "$CHECK"
lunatik stop "$SCRIPT" > /dev/null 2>&1
lunatik stop "$CHECK" > /dev/null 2>&1
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "spawn: a script whose name carries an underscore names its thread after its last two components"

ktap_totals

