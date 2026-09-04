#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the percpu refusal: a registration a percpu instance
# cannot own must fail at load, naming percpu, and the rollback must leave
# nothing registered; the same script runs fine as a plain runtime. Covered
# here by device.new, whose registration is global.
#
# Usage: sudo bash tests/runtime/percpu_refuse.sh

SCRIPT="tests/runtime/percpu_refuse"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

refuse()
{
	local script="$1"
	shift
	local output listed
	output=$(lunatik run "$script" "$@" percpu 2>&1)
	echo "$output" | grep -q "not allowed in a percpu runtime" || \
		fail "percpu run did not refuse the registration: $output"
	listed=$(lunatik list)
	case "$listed" in
		*"$script"*) fail "the refused run left instances behind: $listed" ;;
	esac
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

refuse "$SCRIPT"
[ -e /dev/percpu_refuse ] && fail "the refused run left the device registered"
ktap_pass "global registration fails at load in a percpu instance"

mark_dmesg
run_script "$SCRIPT"
[ -e /dev/percpu_refuse ] || fail "plain run did not register the device"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "the same script runs as a plain runtime"

ktap_totals

