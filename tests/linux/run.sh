#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Harshdeep Singh
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all linux tests and reports aggregated KTAP results.
#
# notifier: linux.netdev carries the events of enum netdev_cmd and linux.vt the notifier events of
# <linux/vt.h>, and neither carries another name under its prefix. The case reads the names and no
# value: enum netdev_cmd is internal, and the kernel renumbers it when it inserts an event.
#
# netns: linux.netns resolves pid 1 in a process runtime, in its body and resumed
# past it, and in the body of a softirq and a hardirq runtime; resumed past theirs,
# the armed state a hook calls from, each answers the call without a pid and
# refuses a pid. The case runs on a build without the refusal too: the resume takes
# the runtime's lock in process context, which cannot have interrupted a holder of
# the task's lock on its CPU, so such a build resolves the pid and fails, not spins.
#
# errname: linux.errname names an errno given with either sign and answers "unknown"
# for INT_MAX and -INT_MAX; it refuses INT_MIN, whose absolute value an int cannot
# hold, and a number past an int, as out of bounds, where a truncating build names
# (1 << 32) | ENOENT as ENOENT.
# ifindex: linux.ifindex resolves lo to its index and linux.hwaddr that index to
# lo's address, and each answers nil, alone, for a name or an index no device has.
#
# Usage: sudo bash tests/linux/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="random fsnotify notifier lookup constants schedule netns errname ifindex"
TOTAL=$(echo $TESTS | wc -w)

# lunatik_lookup reaches kallsyms_lookup_name through a kprobe, so without kprobes every lookup is nil
CONFIG=$({ zcat /proc/config.gz || cat "/boot/config-$(uname -r)"; } 2>/dev/null)

MODULE=lualinux
REFUSAL="not allowed once the runtime is armed"

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

