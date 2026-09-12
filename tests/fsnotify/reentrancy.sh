#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A callback that opens the file it watches returns instead of deadlocking.
#
# The callback runs inside the syscall of the process performing the access,
# with the runtime lock held. Its own io.open of the marked file lands back in
# handle_inode_event on the same task; without the guard that second delivery
# would take the runtime mutex it already holds and the reading process would
# hang in D state for good.
#
# The guard is not proved by removing it: that reproduces the hang, and a task
# stuck in an uninterruptible syscall costs the shared host a reboot. What
# discriminates instead is observer.lua, a second script in its own runtime
# marking the same file: its lock is never the held one, so it reports both
# opens. Two notes from the observer against one delivery to the guarded
# callback is the guard skipping a nested event that did reach the dispatcher,
# rather than an io.open that never produced one.
#
# Usage: sudo bash tests/fsnotify/reentrancy.sh

SCRIPT="tests/fsnotify/reentrancy"
OBSERVER="tests/fsnotify/observer"
SCRATCH="/tmp/lunatik-fsnotify"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$OBSERVER" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/watched"

ktap_header
ktap_plan 4

mark_dmesg
run_script "$OBSERVER"
run_script "$SCRIPT"

timeout 10 cat "$SCRATCH/watched" > /dev/null
opened=$?
output=$(dmesg_since)

lunatik stop "$SCRIPT" 2>/dev/null
lunatik stop "$OBSERVER" 2>/dev/null

[ "$opened" -eq 0 ] || fail "opening the marked file did not return (exit $opened)"
ktap_pass "opening a file whose callback opens it again returns"

echo "$output" | grep -qF "fsnotify reentrancy test pass" || \
	fail "the callback did not run: $(echo "$output" | grep -F 'fsnotify reentrancy test')"
ktap_pass "the callback opened the marked file and returned"

echo "$output" | grep -qF "fsnotify reentrancy test fail" && \
	fail "the callback re-entered instead of being skipped"
ktap_pass "the nested event was skipped, not delivered"

seen=$(echo "$output" | grep -cF "fsnotify observer test note")
[ "$seen" -eq 2 ] || fail "the observer saw $seen opens, expected the read plus the callback's"
ktap_pass "the skipped event did reach fsnotify, the observer saw both opens"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

