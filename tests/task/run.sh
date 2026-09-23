#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all task tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/task/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
SCRIPT="tests/task/task"
SCRIPT_SOFTIRQ="tests/task/softirq"

source "$DIR/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$SCRIPT_SOFTIRQ" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

if run_test "$SCRIPT"; then
	ktap_pass "task/task"
else
	ktap_fail "task/task"
fi

if run_test "$SCRIPT_SOFTIRQ" softirq; then
	ktap_pass "task/softirq"
else
	ktap_fail "task/softirq"
fi

ktap_totals

