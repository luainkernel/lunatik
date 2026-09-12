#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# FS_ACCESS_PERM gates the read and not the open that precedes it.
#
# The two halves are separate hooks: fsnotify_open_perm runs inside
# do_dentry_open, fsnotify_file_area_perm inside rw_verify_area, and this mark
# carries only the second. So the shell opens the file on a descriptor of its
# own, which has to succeed, and then reads from it, which has to fail; a test
# that used cat could not tell the two apart. The file is on the tmpfs the test
# mounted, and the last case reads it once the watch is stopped.
#
# Usage: sudo bash tests/fsnotify/access.sh

SCRIPT="tests/fsnotify/access"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/perm.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$PROBE" 2>/dev/null
	{ exec 3<&-; } 2>/dev/null
	umount "$MOUNT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

perm_begin 5 "fsnotify/access"

echo content > "$MOUNT/gated"

mark_dmesg
run_script "$SCRIPT"
{ exec 3< "$MOUNT/gated"; } 2>/dev/null
opened=$?
read -r line <&3 2>/dev/null
got=$?
{ exec 3<&-; } 2>/dev/null
output=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null
after=$(cat "$MOUNT/gated" 2>&1)

[ "$opened" -eq 0 ] || fail "a mark for FS_ACCESS_PERM gated the open (exit $opened)"
ktap_pass "a mark for FS_ACCESS_PERM does not gate the open"

[ "$got" -ne 0 ] || fail "the denied read returned: $line"
ktap_pass "a callback returning DENY fails the read"

echo "$output" | grep -qF "access test: $MOUNT/gated mask 20000" || \
	fail "the callback did not see the read: $(echo "$output" | grep -F 'fsnotify access test')"
ktap_pass "the event the callback denied is FS_ACCESS_PERM"

[ "$after" = content ] || fail "the read did not return the content after the watch stopped: $after"
ktap_pass "the denial ends with the watch that made it"

errs=$(echo "$output" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

