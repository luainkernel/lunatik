#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A directory mark gates the files inside it, and a directory's own listing.
#
# A rule names a directory more often than a file, and a directory mark reaches
# a permission event two ways that the file marks above do not exercise.
# FS_OPEN_PERM with FS_EVENT_ON_CHILD on a directory decides the open of a file
# inside it, through the parent iterator, while the directory's own open is
# left allowed so it can still be listed. FS_ACCESS_PERM on a directory decides
# its listing, which iterate_dir asks for with MAY_READ, while a file inside is
# still read, since that mark carries no FS_EVENT_ON_CHILD. Both marks are on
# directories of the tmpfs the test mounts, and the last case reads the gated
# file again once the watch is stopped.
#
# Usage: sudo bash tests/fsnotify/directory.sh

SCRIPT="tests/fsnotify/directory"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/perm.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$PROBE" 2>/dev/null
	umount "$MOUNT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

perm_begin 7 "fsnotify/directory"

mkdir "$MOUNT/inside" "$MOUNT/listed"
echo content > "$MOUNT/inside/file"
echo content > "$MOUNT/listed/file"

mark_dmesg
run_script "$SCRIPT"
denied=$(cat "$MOUNT/inside/file" 2>&1)
status=$?
listing=$(ls "$MOUNT/inside" 2>&1)
listed=$?
refused=$(ls "$MOUNT/listed" 2>&1)
refusedstatus=$?
content=$(cat "$MOUNT/listed/file" 2>&1)
output=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null
after=$(cat "$MOUNT/inside/file" 2>&1)

[ "$status" -ne 0 ] || fail "the open of a file inside the marked directory succeeded: $denied"
ktap_pass "a directory mark with FS_EVENT_ON_CHILD denies the open of a file inside"

[ "$listed" -eq 0 ] && [ "$listing" = file ] || fail "the marked directory itself did not list: $listing"
ktap_pass "the directory's own open stays allowed"

[ "$refusedstatus" -ne 0 ] || fail "the listing of the directory marked for FS_ACCESS_PERM succeeded: $refused"
ktap_pass "a directory mark for FS_ACCESS_PERM denies its listing"

[ "$content" = content ] || fail "a file inside the directory marked for FS_ACCESS_PERM did not read: $content"
ktap_pass "a mark without FS_EVENT_ON_CHILD leaves the files inside alone"

echo "$output" | grep -qF "directory test: $MOUNT/inside/file mask 8010000" && \
	echo "$output" | grep -qF "directory test: $MOUNT/listed mask 40020000" || \
	fail "the callback did not see both events: $(echo "$output" | grep -F 'fsnotify directory test' | tr '\n' ';')"
ktap_pass "the callback saw the child's open and the directory's listing"

[ "$after" = content ] || fail "the gated file did not open after the watch stopped: $after"
ktap_pass "the denial ends with the watch that made it"

errs=$(echo "$output" | grep -E "$KTAP_ERRORS" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

