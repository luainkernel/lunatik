#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs rcu regression tests and reports aggregated KTAP results.
#
# index_whole: an index matches the whole key. On a one-bucket table, a prefix of a
# stored key reads nil and an assignment to it adds an entry instead of replacing the
# longer one, the empty key reads nil until it is set, and two keys alike up to an
# embedded NUL are told apart.
#
# bounds: rcu.table() takes its bucket count from Lua and sizes the object's private
# with it. It accepts the counts it serves, defaults to a usable table, and refuses
# zero (roundup_pow_of_two() is undefined there), a negative, and the counts whose
# byte size wraps; a count it can size but no allocator serves is the allocator's
# memory error, with no kernel warning behind it. A key under LUARCU_MAXKEY bytes
# is stored and one at it is out of bounds where it arrives, not a memory error.
#
# map_next: rcu.map() reads a bucket's keys once and looks each one up before its
# call, so the pointer to the next entry it read before the callback ran is never
# dereferenced after it, where a grace period may have passed. An empty table is
# visited nowhere and one entry among empty buckets once; a key with an embedded
# NUL, the empty key and the longest key reach the callback whole; an error the
# callback raises is rcu.map()'s, with no visit after it. On a one-bucket table a
# callback removes, replaces and adds entries, and one collects the table nothing
# but the call holds, which stays through the collection and is visited whole.
#
# Usage: sudo bash tests/rcu/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="map_values map_foreign bounds index_whole map_next"
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

RESULT=0
ktap_totals || RESULT=1

echo ""
bash "$DIR/map_sync.sh" || RESULT=1

echo ""
bash "$DIR/newobject_oom.sh" || RESULT=1

echo ""
bash "$DIR/bigtable_free.sh" || RESULT=1
echo ""
bash "$DIR/entry_release.sh" || RESULT=1
echo ""
bash "$DIR/object_grace.sh" || RESULT=1
exit $RESULT

