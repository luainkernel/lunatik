#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs fifo regression tests and reports aggregated KTAP results.
#
# bounds: fifo.new() and fifo:pop() take their size from Lua. new() accepts the
# capacities it serves and refuses zero, one (kfifo's own floor), a negative and
# anything past KMALLOC_MAX_SIZE, including a value that __kfifo_alloc()'s unsigned
# int truncated into a small fifo; pop() refuses a size past the capacity, which it
# could never return.
#
# Usage: sudo bash tests/fifo/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="bounds"
TOTAL=$(echo $TESTS | wc -w)

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/fifo/$t" 2>/dev/null
	done
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if run_test "tests/fifo/$t"; then
		ktap_pass "fifo/$t"
	else
		ktap_fail "fifo/$t"
	fi
done

ktap_totals
[ $KTAP_FAIL -eq 0 ]

