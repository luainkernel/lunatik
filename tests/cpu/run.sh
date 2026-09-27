#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs cpu regression tests and reports aggregated KTAP results.
#
# stats: cpu.stats() takes a CPU id from Lua. It answers every online CPU with
# its counters, and refuses an id outside [0, linux.numcpus()) as out of bounds:
# -1, the first id past the possible ones, 2^32 (whose low 32 bits are CPU 0),
# and the integer extremes. The refusal comes before the online test, whose bit
# lookup reads past the mask for an id the cast leaves at or past NR_CPUS, as it
# does -1 and math.maxinteger. A build without the bound does not fail the -1
# case, it reads past the online mask, so the suite skips unless the luacpu it
# runs against carries the refusal: the bound is inline, so no symbol of its own
# is in /proc/kallsyms, and the message is what the installed luacpu.ko has.
#
# Usage: sudo bash tests/cpu/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

MODULE="luacpu"
REFUSAL="out of bounds"

source "$DIR/../lib.sh"

TESTS="stats"
TOTAL=$(echo $TESTS | wc -w)

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/cpu/$t" 2>/dev/null
	done
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

[ ! -e /sys/module/$MODULE ] ||
	[ "$(cat /sys/module/$MODULE/srcversion)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] &&
	grep -qaF "$REFUSAL" "$(modinfo -n $MODULE 2> /dev/null)" || {
	for t in $TESTS; do
		ktap_skip "cpu/$t: the $MODULE it runs against does not carry the bound: an unbounded id would read past the online mask"
	done
	ktap_totals
	exit 0
}

for t in $TESTS; do
	if run_test "tests/cpu/$t"; then
		ktap_pass "cpu/$t"
	else
		ktap_fail "cpu/$t"
	fi
done

ktap_totals

