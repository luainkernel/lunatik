#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all lunatik test suites.
#
# Usage: sudo bash tests/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

run_suite() {
	local output
	output=$(bash "$1")
	local ret=$?
	echo "$output"
	while IFS= read -r totals; do
		TOTAL_PASS=$((TOTAL_PASS + $(echo "$totals" | grep -oP 'pass:\K[0-9]+' || echo 0)))
		TOTAL_FAIL=$((TOTAL_FAIL + $(echo "$totals" | grep -oP 'fail:\K[0-9]+' || echo 0)))
		TOTAL_SKIP=$((TOTAL_SKIP + $(echo "$totals" | grep -oP 'skip:\K[0-9]+' || echo 0)))
	done < <(echo "$output" | grep "^# Totals:")
	return $ret
}

run_suite "$DIR/monitor/run.sh"
run_suite "$DIR/thread/run.sh"
run_suite "$DIR/runtime/run.sh"
run_suite "$DIR/socket/run.sh"
run_suite "$DIR/rcu/run.sh"
run_suite "$DIR/crypto/run.sh"
run_suite "$DIR/io/test.sh"
run_suite "$DIR/probe/run.sh"
run_suite "$DIR/notifier/run.sh"

echo ""
echo "# Grand Totals: pass:$TOTAL_PASS fail:$TOTAL_FAIL skip:$TOTAL_SKIP"
[ $TOTAL_FAIL -eq 0 ]

