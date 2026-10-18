#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs fifo regression tests and reports aggregated KTAP results.
#
# bounds: fifo.new() and fifo:pop() take their size from Lua. new() accepts the
# capacities it serves, 4 MiB among them, a block of order 10 where pages are 4 KiB,
# which a machine whose free memory is fragmented serves only from vmalloc, and
# refuses zero, one (kfifo's own floor), a negative and anything past
# KMALLOC_MAX_SIZE, including a value that kfifo_init()'s unsigned int would
# truncate into a small fifo; pop() refuses a size past the capacity, which it
# could never return, and push() a string past it, which no pop makes room for.
# No case forces the vmalloc fallback, which needs fault injection.
#
# push: fifo:push() answers true, alone, while the fifo has room for every byte,
# and false when it has not, taking none of them.
#
# close: fifo:close() closes a fifo of a megabyte, whose buffer may come from
# vmalloc, in a process runtime and in a softirq runtime resumed past its body,
# which runs with bottom halves off and IRQs on, where vfree defers the free by
# itself, and a push then raises "closed object"; that softirq runtime also
# creates a fifo of its own past its body, which kmalloc serves there, passes a
# byte through it and closes it at the end of the scope. A refusal keyed on the
# runtime's context rather than on IRQs raises in the softirq runtime and fails
# the case.
#
# Usage: sudo bash tests/fifo/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="bounds push close"
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

