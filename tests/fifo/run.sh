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
#
# push: fifo:push() answers true, alone, while the fifo has room for every byte,
# and false when it has not, taking none of them.
#
# close: fifo:close() closes a fifo of a megabyte, whose buffer may come from
# vmalloc, in a process runtime, once a message has passed through it, and in a
# softirq runtime resumed past its body, which runs with bottom halves off and
# IRQs on, where vfree defers the free by itself, and a push then raises
# "closed object"; that softirq runtime also creates a fifo of its own past its
# body, which kmalloc serves there, passes a byte through it and closes it at
# the end of the scope. A refusal keyed on the runtime's context rather than on
# IRQs raises in the softirq runtime and fails the case.
#
# fallback: close runs again under a kprobe program on should_fail_alloc_page
# that refuses an allocation of a megabyte to tasks named lunatik, the CLI that
# runs it, and counts each refusal, so that kvmalloc serves its two fifos of a
# megabyte from vmalloc: the process runtime frees one with vfree, and the
# softirq runtime the other through vfree_atomic, since vfree defers whenever
# bottom halves are off. The case passes when close passes and the program
# refused both kmalloc attempts, a count read once the program is detached; a
# fifo.new that takes its buffer from kmalloc alone raises there. Skips without
# clang, bpftool, BTF, CONFIG_BPF_KPROBE_OVERRIDE or should_fail_alloc_page,
# which kernels from 6.11 build only with CONFIG_FAIL_PAGE_ALLOC.
#
# Usage: sudo bash tests/fifo/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
OVERRIDE="/sys/fs/bpf/fifo_fallback"
REFUSALS=2 # one per fifo of a megabyte close.lua creates

source "$DIR/../lib.sh"

TESTS="bounds push close"
TOTAL=$(($(echo $TESTS | wc -w) + 1))

cleanup() {
	rm -rf "$OVERRIDE"
	for t in $TESTS; do
		lunatik stop "tests/fifo/$t" 2>/dev/null
	done
}
trap cleanup EXIT
cleanup

fallback() {
	local name="fifo/fallback" config ran refused
	config=$({ zcat /proc/config.gz || cat "/boot/config-$(uname -r)"; } 2>/dev/null)
	if ! command -v clang > /dev/null 2>&1 || ! command -v bpftool > /dev/null 2>&1; then
		ktap_skip "$name: needs clang and bpftool"
	elif [ ! -f /sys/kernel/btf/vmlinux ]; then
		ktap_skip "$name: needs BTF"
	elif [ -n "$config" ] && ! grep -q '^CONFIG_BPF_KPROBE_OVERRIDE=y' <<< "$config"; then
		ktap_skip "$name: needs CONFIG_BPF_KPROBE_OVERRIDE"
	elif ! grep -qw should_fail_alloc_page /proc/kallsyms; then
		ktap_skip "$name: needs should_fail_alloc_page"
	elif ! make -s -C "$DIR"; then
		ktap_fail "$name: the program does not build"
	elif ! mkdir "$OVERRIDE" ||
		! bpftool prog load "$DIR/fallback.bpf.o" "$OVERRIDE/link" autoattach pinmaps "$OVERRIDE"; then
		rm -rf "$OVERRIDE"
		ktap_fail "$name: the program does not attach"
	else
		lunatik stop tests/fifo/close 2>/dev/null # close's own case left it running
		run_test tests/fifo/close
		ran=$?
		rm "$OVERRIDE/link"
		refused=$(bpftool map lookup pinned "$OVERRIDE/refused" key 0 0 0 0 | awk '/"value"/ { print $2 }')
		rm -rf "$OVERRIDE"
		if [ "$ran" -ne 0 ]; then
			ktap_fail "$name"
		elif [ "$refused" != "$REFUSALS" ]; then
			ktap_fail "$name: the program refused ${refused:-none} of the $REFUSALS kmalloc attempts"
		else
			ktap_pass "$name"
		fi
	fi
}

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if run_test "tests/fifo/$t"; then
		ktap_pass "fifo/$t"
	else
		ktap_fail "fifo/$t"
	fi
done

fallback

ktap_totals

