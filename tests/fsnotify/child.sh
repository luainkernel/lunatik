#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A directory mark reports events on the files inside it only when its mask
# carries FS_EVENT_ON_CHILD.
#
# child.lua marks $SCRATCH with FS_OPEN | FS_EVENT_ON_CHILD and prints a verdict
# carrying the mask it received: opening $SCRATCH/file must deliver FS_OPEN with
# FS_EVENT_ON_CHILD set, the way the kernel tags an event it reports to a
# parent. nochild.lua marks $SCRATCH with FS_OPEN alone: opening the same file
# must deliver nothing, and opening the directory itself must still deliver
# FS_OPEN | FS_ISDIR, so the negative half cannot pass on a watch that stopped
# working.
#
# Usage: sudo bash tests/fsnotify/child.sh

SCRIPT="tests/fsnotify/child"
NOCHILD="tests/fsnotify/nochild"
SCRATCH="/tmp/lunatik-fsnotify"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$NOCHILD" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/file"

ktap_header
ktap_plan 4

mark_dmesg
run_script "$SCRIPT"
cat "$SCRATCH/file" > /dev/null
child=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null

mark_dmesg
run_script "$NOCHILD"
cat "$SCRATCH/file" > /dev/null
unmarked=$(dmesg_since)

mark_dmesg
ls "$SCRATCH" > /dev/null
self=$(dmesg_since)
lunatik stop "$NOCHILD" 2>/dev/null

echo "$child" | grep -qF "fsnotify child test pass" || \
	fail "no FS_OPEN for a file under the marked directory: $(echo "$child" | grep -F 'fsnotify child test')"
ktap_pass "a directory mark with FS_EVENT_ON_CHILD reports a child's FS_OPEN"

echo "$unmarked" | grep -qF "fsnotify nochild test" && \
	fail "a directory mark without FS_EVENT_ON_CHILD reported a child's open"
ktap_pass "a directory mark without FS_EVENT_ON_CHILD reports nothing for a child"

echo "$self" | grep -qF "fsnotify nochild test pass" || \
	fail "no FS_OPEN for the marked directory itself: $(echo "$self" | grep -F 'fsnotify nochild test')"
ktap_pass "a directory mark without FS_EVENT_ON_CHILD still reports its own FS_OPEN"

errs=$(printf '%s\n%s\n%s\n' "$child" "$unmarked" "$self" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

