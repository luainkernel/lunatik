#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A reader of an rcu.table takes its reference on an entry's string under
# rcu_read_lock alone, and a writer that replaces the entry puts the string's
# last reference at once: the string's memory outlives the grace period, and
# the reader takes the reference unless the count is zero, in which case the
# entry reads as gone. string_grace spawns a reader that reads one key, by
# index and through rcu.foreach, checking the bytes of each string it is
# handed, and string_grace_writer, which replaces that key's string with a
# numbered one on every iteration, for a few seconds on two kernel threads; a
# value read is always a whole string or nil, the reader saw the entry
# replaced while it read, without which the two never met on the key, and
# dmesg carries no refcount warning or oops. The window is not forced: the
# case is a stress, and the proof of the mechanism is the trace in the commit.
#
# Skips unless the loaded core carries lunatik_unholdstring, since on a core
# whose strings are freed without a grace period the same stress reads freed
# memory.
#
# Usage: sudo bash tests/rcu/string_grace.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

READER="tests/rcu/string_grace"
WRITER="tests/rcu/string_grace_writer"
SLEEP=4

cleanup() {
	lunatik stop "$WRITER" 2>/dev/null
	lunatik stop "$READER" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

if ! grep -qE ' lunatik_unholdstring(\s|$)' /proc/kallsyms; then
	ktap_skip "rcu/string_grace: the loaded core has no lunatik_unholdstring"
	ktap_totals
	exit 0
fi

mark_dmesg
output=$(lunatik spawn "$READER" 2>&1)
if [ -n "$output" ]; then
	ktap_fail "rcu/string_grace: spawn"
	comment "$output"
	ktap_totals
	exit 1
fi
sleep $SLEEP
cleanup

if dmesg_since | grep -q 'string_grace: '; then
	ktap_fail "rcu/string_grace: the reader reported a failure"
	comment "$(dmesg_since | grep 'string_grace: ')"
elif check_dmesg; then
	ktap_pass "rcu/string_grace"
fi

ktap_totals

