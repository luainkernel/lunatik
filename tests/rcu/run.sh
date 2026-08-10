#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs rcu regression tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/rcu/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="map_values map_foreign"
TOTAL=$(echo $TESTS | wc -w)

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
RESULT=$?

echo ""
bash "$DIR/map_sync.sh" || RESULT=1

echo ""
bash "$DIR/newobject_oom.sh" || RESULT=1

echo ""
bash "$DIR/bigtable_free.sh" || RESULT=1
exit $RESULT

