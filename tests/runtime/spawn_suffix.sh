#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that a script spawned with its ".lua" suffix registers its thread under
# the trimmed name runner.stop looks up, the one `lunatik list` shows: a thread
# registered under the name as given is one the stop skips, and the stop then
# closes the runtime instead, waiting on the lock the thread body holds for as
# long as it runs. The body here returns at once, so the check is the registry.
#
# Usage: sudo bash tests/runtime/spawn_suffix.sh

SCRIPT="tests/runtime/spawn_suffix"
CHECK="tests/runtime/spawn_suffix_check"

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
output=$(lunatik spawn "$SCRIPT.lua" 2>&1)
[ -n "$output" ] && fail "spawn failed: $output"
run_script "$CHECK"
lunatik stop "$SCRIPT" > /dev/null 2>&1
lunatik stop "$CHECK" > /dev/null 2>&1
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "spawn: a script spawned with its .lua suffix registers the thread under the name stop looks up"

ktap_totals

