#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the rollback of a spawn whose thread cannot start: runner.spawn creates
# the runtime through runner.run, which registers it, and only then calls
# thread.run, which refuses an IRQ runtime. The refusal must leave nothing
# registered, so `lunatik list` is the assertion, and the same script spawning
# as a process runtime is what says the refusal is not refusing everything.
#
# Usage: sudo bash tests/runtime/spawn_refuse.sh

SCRIPT="tests/runtime/spawn_refuse"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

refuse()
{
	local context="$1"
	local output listed
	output=$(lunatik spawn "$SCRIPT" "$context" 2>&1)
	echo "$output" | grep -q "IRQ runtime cannot spawn threads" || \
		fail "a $context spawn was not refused: $output"
	listed=$(lunatik list)
	case "$listed" in
		*"$SCRIPT"*) fail "the refused $context spawn left the runtime registered: $listed" ;;
	esac
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

mark_dmesg

refuse softirq
ktap_pass "spawn: a softirq runtime is refused and leaves nothing registered"

refuse hardirq
ktap_pass "spawn: a hardirq runtime is refused and leaves nothing registered"

output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -n "$output" ] && fail "the process spawn failed: $output"
listed=$(lunatik list)
lunatik stop "$SCRIPT" > /dev/null 2>&1
case "$listed" in
	*"$SCRIPT"*) ;;
	*) fail "the process spawn did not register the script: $listed" ;;
esac
listed=$(lunatik list)
case "$listed" in
	*"$SCRIPT"*) fail "the process spawn was not stopped: $listed" ;;
esac
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "spawn: the same script spawns and stops as a process runtime"

ktap_totals

