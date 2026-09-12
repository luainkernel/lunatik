#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A mark placed for FS_OPEN and set to FS_OPEN_PERM afterwards gates the open.
#
# This is the case the group's priority is set for on every group rather than
# on the ones whose first mask asks for a verdict: from 6.10 the open path
# delivers a permission event only where a content-priority group has marked
# the object, and that count is taken when the mark is added. A priority set
# on the first permission mask would leave an object marked earlier uncounted,
# and the event would never arrive; the open would then succeed with nothing
# said on either side. Before 6.10 the case passes either way, so it
# discriminates on 6.10 and later.
#
# Usage: sudo bash tests/fsnotify/upgrade.sh

SCRIPT="tests/fsnotify/upgrade"

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

perm_begin 4 "fsnotify/upgrade"

echo content > "$MOUNT/gated"

mark_dmesg
run_script "$SCRIPT"
denied=$(cat "$MOUNT/gated" 2>&1)
status=$?
output=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null
after=$(cat "$MOUNT/gated" 2>&1)

[ "$status" -ne 0 ] || fail "the open a mask set to FS_OPEN_PERM should gate succeeded: $denied"
ktap_pass "a mark set from FS_OPEN to FS_OPEN_PERM denies the open"

echo "$output" | grep -qF "upgrade test: $MOUNT/gated mask 10000" || \
	fail "the callback did not see the permission event: $(echo "$output" | grep -F 'fsnotify upgrade test')"
ktap_pass "the event the callback denied is the permission event the mask gained"

[ "$after" = content ] || fail "the gated file did not open after the watch stopped: $after"
ktap_pass "the denial ends with the watch that made it"

errs=$(echo "$output" | grep -E "$KTAP_ERRORS" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

