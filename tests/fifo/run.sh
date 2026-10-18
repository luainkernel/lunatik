#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs fifo regression tests and reports aggregated KTAP results.
#
# bounds: fifo.new() and fifo:pop() take their size from Lua. new() accepts the
# capacities it serves, 4 MiB among them, which no free block holds once memory is
# fragmented, and refuses zero, one (kfifo's own floor), a negative and
# anything past KMALLOC_MAX_SIZE, including a value that kfifo_init()'s unsigned
# int truncated into a small fifo; pop() refuses a size past the capacity, which it
# could never return, and push() a string past it, which no pop makes room for.
#
# push: fifo:push() answers true, alone, while the fifo has room for every byte,
# and false when it has not, taking none of them.
#
# close: fifo:close() closes a fifo of a megabyte, whose buffer may be vmalloc'd,
# in a process runtime and in a softirq runtime resumed past its body, which runs
# with bottom halves off and IRQs on, and a push then raises "closed object".
#
# probe: the body of a hardirq runtime, which runs with IRQs on, closes a fifo,
# and the pre handler of a kprobe on the personality syscall, which setarch makes,
# sees fifo:close() raise "not allowed with IRQs disabled": a vmalloc'd buffer is
# one vfree may not release there, and a hardirq runtime takes its lock with
# spin_lock_irqsave for every callback. The fifo is a kmalloc'd one, so a module
# without the refusal closes it and fails the case. Skips without CONFIG_KPROBES or
# setarch.
#
# Usage: sudo bash tests/fifo/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
SCRIPT_PROBE="tests/fifo/probe"
PREFIX="fifo probe: "

source "$DIR/../lib.sh"

TESTS="bounds push close"
TOTAL=$(($(echo $TESTS | wc -w) + 1))

cleanup() {
	for t in $TESTS probe; do
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

probe_refusal "fifo/probe" "$SCRIPT_PROBE" "$PREFIX"

ktap_totals

