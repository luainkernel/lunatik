#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Harshdeep Singh
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs linux module regression tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/linux/run.sh
DIR="$(dirname "$(readlink -f "$0")")"
source "$DIR/../lib.sh"
TESTS="random"
TOTAL=$(echo $TESTS | wc -w)
ktap_header
ktap_plan $TOTAL
for t in $TESTS; do
	if run_test "tests/linux/$t"; then
		ktap_pass "linux/$t"
	else
		ktap_fail "linux/$t"
	fi
done
ktap_totals
[ $KTAP_FAIL -eq 0 ]
