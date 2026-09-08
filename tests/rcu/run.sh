#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs rcu regression tests and reports aggregated KTAP results.
#
# bounds: rcu.table() takes its bucket count from Lua and sizes the object's private
# with it. It accepts the counts it serves, defaults to a usable table, and refuses
# zero (roundup_pow_of_two() is undefined there), a negative, and the counts whose
# byte size wraps; a count it can size but no allocator serves is the allocator's
# memory error, with no kernel warning behind it.
#
# Usage: sudo bash tests/rcu/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="map_values map_foreign bounds"
TOTAL=$(echo $TESTS | wc -w)

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/rcu/$t" 2>/dev/null
	done
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if run_test "tests/rcu/$t"; then
		ktap_pass "rcu/$t"
	else
		ktap_fail "rcu/$t"
	fi
done

ktap_totals
RESULT=0
[ $KTAP_FAIL -eq 0 ] || RESULT=1

echo ""
bash "$DIR/map_sync.sh" || RESULT=1

echo ""
bash "$DIR/newobject_oom.sh" || RESULT=1

echo ""
bash "$DIR/bigtable_free.sh" || RESULT=1
exit $RESULT

