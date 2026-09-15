#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The mark as an object: found by path, removed on its own, and taken by the
# watch that placed it.
#
# marks.lua marks two files, asks the watch for each of them back, marks one
# of them a second time and expects the refusal, and removes the other; the
# shell then reads both, so a mark that survived its removal shows as an event
# and the remaining one proves the watch is still delivering.
# stopped.lua marks two files and stops the watch, which must leave neither the
# marks nor a usable handle.
#
# Both run twice in a row, and each round counts the events rather than looking
# for one: a mark or a group leaked by the first round delivers a second line
# in the second, which a presence test would read as a pass.
#
# Usage: sudo bash tests/fsnotify/marks.sh

SCRIPT="tests/fsnotify/marks"
STOPPED="tests/fsnotify/stopped"
SCRATCH="/tmp/lunatik-fsnotify"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$STOPPED" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/kept"
: > "$SCRATCH/dropped"

ktap_header
ktap_plan 9

for round in 1 2; do
	mark_dmesg
	run_script "$SCRIPT"
	cat "$SCRATCH/kept" > /dev/null
	cat "$SCRATCH/dropped" > /dev/null
	marked=$(dmesg_since)
	lunatik stop "$SCRIPT" 2>/dev/null

	mark_dmesg
	run_script "$STOPPED"
	cat "$SCRATCH/kept" > /dev/null
	cat "$SCRATCH/dropped" > /dev/null
	stopped=$(dmesg_since)
	lunatik stop "$STOPPED" 2>/dev/null

	found=$(echo "$marked" | grep -cF "fsnotify marks test pass:")
	[ "$found" -eq 4 ] || \
		fail "round $round: find: $(echo "$marked" | grep -F 'fsnotify marks test' | tr '\n' ';')"
	ktap_pass "round $round: find returns the mark, nil where there is none, nil after remove; a second mark is refused"

	kept=$(echo "$marked" | grep -cF "marks test: open $SCRATCH/kept")
	[ "$kept" -eq 1 ] || fail "round $round: the kept mark delivered $kept events, expected 1"
	ktap_pass "round $round: the mark that stays delivers once"

	echo "$marked" | grep -qF "marks test: open $SCRATCH/dropped" && \
		fail "round $round: a removed mark still delivered"
	ktap_pass "round $round: a removed mark delivers nothing"

	echo "$stopped" | grep -qF "fsnotify marks test pass: stop takes every mark" || \
		fail "round $round: stop: $(echo "$stopped" | grep -F 'fsnotify marks test' | tr '\n' ';')"
	echo "$stopped" | grep -qF "event after stop" && \
		fail "round $round: an event arrived after stop"
	ktap_pass "round $round: stop removes every mark and leaves no usable handle"

	errs=$(printf '%s\n%s\n' "$marked" "$stopped" | grep -E "\.lua:[0-9]+:" || true)
	[ -n "$errs" ] && fail "round $round: Lua error in kernel: $errs"
done

ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

