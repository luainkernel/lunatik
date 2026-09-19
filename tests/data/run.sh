#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs data regression tests and reports aggregated KTAP results.
#
# bounds: data.new() and data:resize() take the buffer size from Lua. Both accept
# the sizes they serve, round-trip a byte at the far end of the buffer, and refuse
# zero, a negative and anything past INT_MAX, which the allocator cannot serve.
#
# zeroed: what an owned buffer holds before the script writes to it. data.new() and a
# data:resize() that grows come back zeroed, on the krealloc and the kvmalloc arm of the
# allocator and from an atomic runtime. A round poisons its buffers and frees them so
# the next round allocates over them, and a shrink followed by a growth back into the
# block it kept reads the buffer's own bytes and needs no such luck. The sizes read a
# page as 4 KiB, as bounds does; where the kernel's page is larger the size past it stays
# on the krealloc arm and the megabyte case is what reaches kvmalloc. A kernel that zeroes
# every allocation itself reads the same on a fixed data.new and a broken one, so the case
# skips there rather than report a pass it cannot back.
#
# Usage: sudo bash tests/data/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="bounds zeroed"
TOTAL=$(echo $TESTS | wc -w)

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/data/$t" 2>/dev/null
	done
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

# init_on_alloc is an early_param read with kstrtobool, so the command line decides and the config is the default
zeroesallocations() {
	case " $(cat /proc/cmdline) " in
		*" init_on_alloc="[yYtT1]*|*" init_on_alloc="[oO][nN]*) return 0 ;;
		*" init_on_alloc="[nN0]*|*" init_on_alloc="[oO][fF]*) return 1 ;;
	esac
	{ zcat /proc/config.gz 2>/dev/null; cat "/boot/config-$(uname -r)" 2>/dev/null; } |
		grep -q '^CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y'
}

for t in $TESTS; do
	if [ "$t" = zeroed ] && zeroesallocations; then
		ktap_skip "data/$t: init_on_alloc zeroes every allocation here, nothing tells the cases apart"
	elif run_test "tests/data/$t"; then
		ktap_pass "data/$t"
	else
		ktap_fail "data/$t"
	fi
done

ktap_totals
RESULT=0
[ $KTAP_FAIL -eq 0 ] || RESULT=1

echo ""
bash "$DIR/resize_atomic.sh" || RESULT=1
exit $RESULT

