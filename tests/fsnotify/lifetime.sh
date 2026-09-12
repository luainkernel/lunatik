#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The two teardown paths of a watch: the explicit stop, and the release that
# runs when a watch is never stopped and its runtime goes away.
#
# lifetime.lua marks, stops twice and then marks again: the second stop must be
# a no-op and the mark after it must raise, since stop clears the private. The
# shell then reads the marked file, which must deliver nothing.
#
# orphan.lua marks and returns, leaving the watch to the object's release. The
# shell stops the script and then unlinks the marked inode, which is the path
# that walks whatever marks are still attached to it — a group released with
# its marks still installed oopses there rather than silently.
#
# Usage: sudo bash tests/fsnotify/lifetime.sh

SCRIPT="tests/fsnotify/lifetime"
ORPHAN="tests/fsnotify/orphan"
SCRATCH="/tmp/lunatik-fsnotify"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$ORPHAN" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/watched"

ktap_header
ktap_plan 4

mark_dmesg
run_script "$SCRIPT"
cat "$SCRATCH/watched" > /dev/null
stopped=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null

mark_dmesg
run_script "$ORPHAN"
lunatik stop "$ORPHAN" 2>/dev/null
rm -f "$SCRATCH/watched"
released=$(dmesg_since)

echo "$stopped" | grep -qF "fsnotify lifetime test pass" || \
	fail "stop did not behave: $(echo "$stopped" | grep -F 'fsnotify lifetime test')"
ktap_pass "a second stop is harmless and mark raises after it"

echo "$stopped" | grep -qF "event after stop" && fail "an event arrived after stop"
ktap_pass "stop ends delivery"

echo "$released" | grep -qF "fsnotify orphan test pass" || \
	fail "the orphan watch did not arm: $(echo "$released" | grep -F 'fsnotify orphan test')"
ktap_pass "a watch that is never stopped is released with its runtime"

oops=$(printf '%s\n%s\n' "$stopped" "$released" | \
	grep -E "Oops:|BUG:|kernel BUG at|NULL pointer dereference|general protection|\.lua:[0-9]+:" || true)
[ -n "$oops" ] && fail "kernel error during teardown: ${oops%%$'\n'*}"
ktap_pass "no kernel error while unlinking the marked inode"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

