#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A kernel thread that opens a path its own runtime watches returns instead of
# deadlocking.
#
# The body of a spawned script runs under lunatik_run for its whole life, so it
# holds the runtime lock the way a callback does, and it reaches the lock by a
# route the callback never takes. Its io.open of the marked file lands back in
# handle_inode_event on the kthread; the guard reads the lock's owner, so it
# sees the kthread and skips the delivery. Without it the kthread would block on
# the mutex it holds and the stop that waits for it would never return.
#
# The guard is not proved by removing it: that reproduces the hang, and a kernel
# thread stuck on its own mutex costs the shared host a reboot. What
# discriminates instead is observer.lua, a second script in its own runtime
# marking the same file: its lock is never the held one, so it reports the open
# the guarded runtime did not.
#
# Usage: sudo bash tests/fsnotify/thread.sh

SCRIPT="tests/fsnotify/thread"
OBSERVER="tests/fsnotify/observer"
SCRATCH="/tmp/lunatik-fsnotify"
SLEEP=1

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
ktap_plan 3

mark_dmesg
run_script "$OBSERVER"
spawned=$(lunatik spawn "$SCRIPT" 2>&1)
sleep $SLEEP
output=$(dmesg_since)

lunatik stop "$SCRIPT" 2>/dev/null
lunatik stop "$OBSERVER" 2>/dev/null

echo "$output" | grep -qF "fsnotify thread test pass" || \
	fail "the thread body's open did not return: $spawned $(echo "$output" | grep -F 'fsnotify thread test')"
ktap_pass "a thread body that opens the path its runtime watches returns"

echo "$output" | grep -qF "fsnotify thread test fail" && \
	fail "the event was delivered on the lock the thread body holds"
ktap_pass "the nested event was skipped, not delivered"

seen=$(echo "$output" | grep -cF "fsnotify observer test note")
[ "$seen" -eq 1 ] || fail "the observer saw $seen opens, expected the thread body's"
ktap_pass "the skipped event did reach fsnotify, the observer saw the open"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

