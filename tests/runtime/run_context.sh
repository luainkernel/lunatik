#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the context runner.run gives a runtime, in the two spellings its second
# argument takes: a string, and the context field of a table. The script creates a
# socket, which a softirq runtime refuses, so the refusal is what says the context
# reached the runtime, and it must leave nothing registered; the same script run as
# a process runtime, in either spelling, is what says the refusal is not refusing
# everything.
#
# Usage: sudo bash tests/runtime/run_context.sh

SCRIPT="tests/runtime/run_context"
REFUSAL="'socket': process-context class in interrupt-context runtime"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

# runs the script with $1, Lua source, as the second argument of runner.run
run()
{
	output=$(lunatik -e "lunatik.runner.run('$SCRIPT', $1)" 2>&1)
	listed=$(lunatik list)
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

refused()
{
	run "$1"
	echo "$output" | grep -qF "$REFUSAL" || fail "a run with $1 was not refused: $output"
	case "$listed" in
		*"$SCRIPT"*) fail "the refused run with $1 left the script registered: $listed" ;;
	esac
}

ran()
{
	run "$1"
	[ -z "$output" ] || fail "a run with $1 failed: $output"
	case "$listed" in
		*"$SCRIPT"*) ;;
		*) fail "a run with $1 did not register the script: $listed" ;;
	esac
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

mark_dmesg

refused "'softirq'"
ran "'process'"
ktap_pass "run: a string is the context of the runtime"

refused "{context = 'softirq'}"
ran "{context = 'process'}"
ktap_pass "run: the context field of a table is the context of the runtime"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

