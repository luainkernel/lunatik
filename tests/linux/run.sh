#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Harshdeep Singh
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all linux tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/linux/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="random fs lookup constants schedule"
TOTAL=$(echo $TESTS | wc -w)

# lunatik_lookup reaches kallsyms_lookup_name through a kprobe, so without kprobes every lookup is nil
CONFIG=$({ zcat /proc/config.gz || cat "/boot/config-$(uname -r)"; } 2>/dev/null)

MODULE=lualinux
REFUSAL="not allowed after module load"

# a lualinux without the refusal sleeps under an armed runtime's spinlock, and a run by hand reaches what is loaded
carries_refusal() {
	[ "$(cat /sys/module/$MODULE/srcversion 2> /dev/null)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] &&
		grep -aqF "$REFUSAL" "$(modinfo -n $MODULE 2> /dev/null)"
}

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/linux/$t" 2>/dev/null
	done
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if [ "$t" = lookup ] && [ -n "$CONFIG" ] && ! grep -q '^CONFIG_KPROBES=y' <<< "$CONFIG"; then
		ktap_skip "linux/$t: needs CONFIG_KPROBES"
		continue
	fi
	if [ "$t" = schedule ] && ! carries_refusal; then
		ktap_skip "linux/$t: the loaded $MODULE does not carry the refusal in schedule"
		continue
	fi
	if run_test "tests/linux/$t"; then
		ktap_pass "linux/$t"
	else
		ktap_fail "linux/$t"
	fi
done

ktap_totals

