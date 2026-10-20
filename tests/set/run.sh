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
# image: set.image over the images write.lua writes from the lists below, which answer what set.new
# answers over the same members and labels, read by set.image.load; what data.load raises,
# raised as it is; and copies of a valid file each broken at one rule, which raise naming it,
# after the path: the header's, not a set image, unsupported version, unknown flags and size
# mismatch; and an offset above the next or past the file, whose member a lookup answers as none.
#
# Usage: sudo bash tests/set/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="set data image"
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

# setimage <name> <lines>: the image write.lua writes from <lines>, in printf's escapes
setimage() {
	printf "$2" > "$SCRATCH/$1.txt" && lua5.5 "$WRITER" "$SCRATCH/$1.txt" "$SCRATCH/$1.set"
}

# breaks <name> <file> <offset> <bytes>: a copy of <file> with <bytes>, in printf's escapes, at <offset>
breaks() {
	cp "$SCRATCH/$2.set" "$SCRATCH/$1.set" &&
		printf "$4" | dd of="$SCRATCH/$1.set" bs=1 seek="$3" conv=notrunc status=none
}

# ab is LSET, version 1, flags 0, n 2, len 2 at 0..15, off 0 1 2 at 16..27 and "ab" at 28
prepare() {
	mkdir -p "$SCRATCH" &&
	setimage list 'delta\nalpha\n\ncharlie\nbravo\nalpha\n' &&
	setimage map 'c 1\nb.c 2\na.b.c 4\nk 4294967295\n' &&
	setimage empty '' &&
	setimage ab 'b\na\n' &&
	breaks magic ab 0 'X' &&
	head -c 15 "$SCRATCH/ab.set" > "$SCRATCH/short.set" &&
	breaks version ab 4 '\x02' &&
	breaks flags ab 6 '\x02' &&
	head -c 29 "$SCRATCH/ab.set" > "$SCRATCH/truncated.set" &&
	{ cat "$SCRATCH/ab.set"; printf 'x'; } > "$SCRATCH/trailing.set" &&
	breaks count ab 8 '\xff\xff\xff\xff' &&
	breaks length ab 12 '\x03' &&
	breaks decreasing ab 20 '\x03' &&
	breaks past ab 24 '\x03' &&
	breaks emptymap empty 6 '\x01'
}

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if [ "$t" = image ] && ! prepare; then
		ktap_fail "set/$t: write.lua did not write the files it loads"
	elif run_test "tests/set/$t"; then
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

