#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs data regression tests and reports aggregated KTAP results.
#
# bounds: data.new() and data:resize() take the buffer size from Lua. Both accept
# the sizes they serve, round-trip a byte at the far end of the buffer, and refuse
# zero, a negative and anything past INT_MAX, which the allocator cannot serve.
#
# Usage: sudo bash tests/data/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="bounds"
TOTAL=$(echo $TESTS | wc -w)

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/data/$t" 2>/dev/null
	done
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if run_test "tests/data/$t"; then
		ktap_pass "data/$t"
	else
		ktap_fail "data/$t"
	fi
done

ktap_totals
RESULT=0
[ $KTAP_FAIL -eq 0 ] || RESULT=1

echo ""
bash "$DIR/resize_atomic.sh" || RESULT=1
exit $RESULT

