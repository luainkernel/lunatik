#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A callback returning DENY fails the open with EPERM, and only that open.
#
# The denial is what the module exists for and what makes it dangerous, so this
# test bounds it three ways: the two marks are on files of a tmpfs the test
# mounted, the rule names one of them, and the neighbour it does not name is
# read in the same run to show the deny is a decision and not a broken verdict
# path. The last case reads the denied file again after the watch is stopped:
# a rule that outlived its script would be a machine left unable to read a file.
# A third file answers -4095, the last value the kernel reads as an errno: it has
# to fail with that number, which pins the clamp's edge from the denying side;
# default.sh pins the other side.
#
# Usage: sudo bash tests/fsnotify/deny.sh

SCRIPT="tests/fsnotify/deny"

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

perm_begin 6 "fsnotify/deny"

echo classified > "$MOUNT/secret"
echo readable > "$MOUNT/public"
echo boundary > "$MOUNT/edge"

mark_dmesg
run_script "$SCRIPT"
denied=$(cat "$MOUNT/secret" 2>&1)
status=$?
allowed=$(cat "$MOUNT/public" 2>&1)
edge=$(cat "$MOUNT/edge" 2>&1)
edgestatus=$?
output=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null
after=$(cat "$MOUNT/secret" 2>&1)

[ "$status" -ne 0 ] || fail "the denied open succeeded and read: $denied"
ktap_pass "a callback returning DENY fails the open"

echo "$denied" | grep -qi "not permitted" || fail "the denied open failed with: $denied"
ktap_pass "the denied open fails with EPERM"

[ "$allowed" = readable ] || fail "the neighbouring file did not open: $allowed"
ktap_pass "a file the rule does not name still opens"

[ "$edgestatus" -ne 0 ] && echo "$edge" | grep -q 4095 || fail "the open a callback answered -4095 got: $edge"
ktap_pass "a callback returning the last errno the kernel recognises denies with it"

[ "$after" = classified ] || fail "the denied file did not open after the watch stopped: $after"
ktap_pass "the denial ends with the watch that made it"

errs=$(echo "$output" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

