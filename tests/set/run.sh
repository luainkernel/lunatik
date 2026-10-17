#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs set regression tests and reports aggregated KTAP results.
#
# set: set.new from a list or a map, has, match and # (see tests/README.md).
# load: set.load over the files write.lua writes from the lists below, which
# answer what set.new answers over the same members and labels, and over copies of
# them each broken at one rule of the layout, which raise naming that rule; the
# errnos of the read, busy.set held open for writing while it runs among them, and
# the refusal once an interrupt-context runtime is armed.
#
# Usage: sudo bash tests/set/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="set load"
TOTAL=$(echo $TESTS | wc -w)
SCRATCH="/tmp/lunatik-set"
WRITER="/lib/modules/lua/tests/set/write.lua"

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/set/$t" 2>/dev/null
	done
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

# setfile <name> <lines>: the file write.lua writes from <lines>, in printf's escapes
setfile() {
	printf "$2" > "$SCRATCH/$1.txt" && lua5.5 "$WRITER" "$SCRATCH/$1.txt" "$SCRATCH/$1.set"
}

# breaks <name> <file> <offset> <bytes>: a copy of <file> with <bytes>, in printf's escapes, at <offset>
breaks() {
	cp "$SCRATCH/$2.set" "$SCRATCH/$1.set" &&
		printf "$4" | dd of="$SCRATCH/$1.set" bs=1 seek="$3" conv=notrunc status=none
}

# ab is LSET, version 1, flags 0, n 2, len 2 at 0..15, off 0 1 2 at 16..27 and "ab" at 28;
# labeled carries flags 1 at 6, labels 1 2 at 28..35 and "ab" at 36
prepare() {
	mkdir -p "$SCRATCH/dir" &&
	setfile list 'delta\nalpha\n\ncharlie\nbravo\nalpha\n' &&
	setfile map 'c 1\nb.c 2\na.b.c 4\nk 4294967295\n' &&
	setfile empty '' &&
	setfile ab 'b\na\n' &&
	setfile labeled 'a 1\nb 2\n' &&
	: > "$SCRATCH/zero.set" &&
	breaks magic ab 0 'X' &&
	head -c 15 "$SCRATCH/ab.set" > "$SCRATCH/short.set" &&
	breaks version ab 4 '\x02' &&
	breaks flags ab 6 '\x02' &&
	head -c 29 "$SCRATCH/ab.set" > "$SCRATCH/truncated.set" &&
	{ cat "$SCRATCH/ab.set"; printf 'x'; } > "$SCRATCH/trailing.set" &&
	breaks count ab 8 '\xff\xff\xff\xff' &&
	breaks length ab 12 '\x03' &&
	breaks first ab 16 '\x01' &&
	breaks last ab 24 '\x01' &&
	breaks decreasing ab 20 '\x03' &&
	breaks unsorted ab 28 'ba' &&
	breaks repeated ab 28 'aa' &&
	breaks unlabeled labeled 28 '\x00' &&
	breaks emptymap empty 6 '\x01' &&
	cp "$SCRATCH/list.set" "$SCRATCH/busy.set" &&
	exec 3>> "$SCRATCH/busy.set"
}

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if [ "$t" = load ] && ! prepare; then
		ktap_fail "set/$t: write.lua did not write the files it loads"
	elif run_test "tests/set/$t"; then
		ktap_pass "set/$t"
	else
		ktap_fail "set/$t"
	fi
done

ktap_totals

