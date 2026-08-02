#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs set regression tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/set/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="set"
TOTAL=$(echo $TESTS | wc -w)

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if run_test "tests/set/$t"; then
		ktap_pass "set/$t"
	else
		ktap_fail "set/$t"
	fi
done

ktap_totals

