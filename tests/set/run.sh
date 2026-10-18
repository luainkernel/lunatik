#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs set regression tests and reports aggregated KTAP results.
#
# set: set.new from a list or a map, has, match and # (see tests/README.md).
# data: set.fromdata over a data the script writes, its offsets and labels where the layout puts
# them, which answers what set.new answers over a table of the same members and labels; the
# data read only from then on, a refused layout included, and still reading; a layout field
# outside the data and an array past it or at an offset not a multiple of 4, each refused as out
# of bounds; a member whose offsets reach past the data, far past it or end before they start,
# answered as no member and read nowhere outside the data; a layout that is not a table,
# which leaves the data writable, or lacks a field, an object other than a data and a value that
# is no object, each refused naming it; set.new refusing a data at its first argument; and the set
# answering from a softirq runtime once the script's handle on its data is collected. view.sh, run
# after the others, refuses a packet's view.
#
# Usage: sudo bash tests/set/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="set data"
TOTAL=$(echo $TESTS | wc -w)

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/set/$t" 2>/dev/null
	done
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if run_test "tests/set/$t"; then
		ktap_pass "set/$t"
	else
		ktap_fail "set/$t"
	fi
done

RESULT=0
ktap_totals || RESULT=1

echo ""
bash "$DIR/view.sh" || RESULT=1
exit $RESULT

