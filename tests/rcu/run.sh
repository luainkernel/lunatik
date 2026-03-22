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

TESTS="map_values"
TOTAL=$(echo $TESTS | wc -w)

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	mark_dmesg
	if ! lunatik run "tests/rcu/$t" 2>/dev/null; then
		ktap_fail "rcu/$t: script execution failed"
		continue
	fi
	errs=$(dmesg | tail -n +$((DMESG_LINE+1)) | grep -iE "^[^:]+: FAIL	|\.lua:[0-9]+:" || true)
	if [ -z "$errs" ]; then
		ktap_pass "rcu/$t"
	else
		ktap_fail "rcu/$t"
		while IFS= read -r line; do
			echo "# $line"
		done <<< "$errs"
	fi
done

ktap_totals
RESULT=$?

echo ""
bash "$DIR/map_sync.sh" || RESULT=1
exit $RESULT

