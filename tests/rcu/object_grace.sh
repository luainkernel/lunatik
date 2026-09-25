#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A reader of an rcu.table takes its reference on an entry's object under
# rcu_read_lock alone, and a writer that replaces the entry puts the object's
# last reference at once: the object's memory outlives the grace period, and
# the reader takes the reference unless the count is zero, in which case the
# entry reads as gone. object_grace spawns a reader that reads one key, by
# index and through rcu.map, touching the object each hands it, and
# object_grace_writer, which replaces that key's data object on every
# iteration, for a few seconds on two kernel threads; a value read is always a
# usable object or nil, the reader saw the entry replaced while it read,
# without which the two never met on the key, and dmesg carries no refcount
# warning or oops. The window is not forced: the case is a stress, and the
# proof of the mechanism is the trace in the commit.
#
# Skips unless the loaded core carries lunatik_getobject_rcu, since on a core
# without it the same stress reads freed memory.
#
# Usage: sudo bash tests/rcu/object_grace.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

READER="tests/rcu/object_grace"
WRITER="tests/rcu/object_grace_writer"
SLEEP=4

cleanup() {
	lunatik stop "$WRITER" 2>/dev/null
	lunatik stop "$READER" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

if ! grep -qE ' lunatik_getobject_rcu(\s|$)' /proc/kallsyms; then
	ktap_skip "rcu/object_grace: the loaded core has no lunatik_getobject_rcu"
	ktap_totals
	exit 0
fi

mark_dmesg
output=$(lunatik spawn "$READER" 2>&1)
if [ -n "$output" ]; then
	ktap_fail "rcu/object_grace: spawn"
	comment "$output"
	ktap_totals
	exit 1
fi
sleep $SLEEP
cleanup

if dmesg_since | grep -q 'object_grace: '; then
	ktap_fail "rcu/object_grace: the reader reported a failure"
	comment "$(dmesg_since | grep 'object_grace: ')"
elif check_dmesg; then
	ktap_pass "rcu/object_grace"
fi

ktap_totals

