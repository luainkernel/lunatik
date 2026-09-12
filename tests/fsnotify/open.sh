#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# An inode mark reports the events in its mask for the file it was placed on,
# and nothing for a neighbour in the same directory.
#
# The kernel script marks $SCRATCH/watched for FS_OPEN and prints a verdict
# carrying the mask it received, so a wrong mask reads as a failure rather than
# as a missing event. Opening $SCRATCH/other must produce nothing: that is what
# separates a mark on the inode from one on its directory.
#
# Usage: sudo bash tests/fsnotify/open.sh

SCRIPT="tests/fsnotify/open"
SCRATCH="/tmp/lunatik-fsnotify"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/watched"
: > "$SCRATCH/other"

ktap_header
ktap_plan 3

mark_dmesg
run_script "$SCRIPT"

cat "$SCRATCH/watched" > /dev/null
marked=$(dmesg_since)

mark_dmesg
cat "$SCRATCH/other" > /dev/null
neighbour=$(dmesg_since)

lunatik stop "$SCRIPT" 2>/dev/null

echo "$marked" | grep -qF "fsnotify open test pass" || \
	fail "no FS_OPEN for the marked file: $(echo "$marked" | grep -F 'fsnotify open test')"
ktap_pass "an inode mark reports FS_OPEN for the file it marks"

echo "$neighbour" | grep -qF "fsnotify open test" && \
	fail "the callback ran for an unmarked neighbour"
ktap_pass "an unmarked neighbour reports nothing"

errs=$(printf '%s\n%s\n' "$marked" "$neighbour" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

