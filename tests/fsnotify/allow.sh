#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A callback returning ALLOW lets the open through.
#
# This is the case a broken verdict path breaks silently: a module that answers
# every permission event with a denial passes any test that only asserts
# denials, so the success is asserted first and on both halves at once. The read
# has to return the file's content, and the callback has to have seen the open
# that produced it, which a mark that never fired would not.
#
# Usage: sudo bash tests/fsnotify/allow.sh

SCRIPT="tests/fsnotify/allow"

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

perm_begin 3 "fsnotify/allow"

echo content > "$MOUNT/gated"

mark_dmesg
run_script "$SCRIPT"
content=$(cat "$MOUNT/gated" 2>&1)
output=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null

[ "$content" = content ] || fail "the allowed open did not read the file: $content"
ktap_pass "a callback returning ALLOW lets the open through"

echo "$output" | grep -qF "allow test: $MOUNT/gated mask 10000" || \
	fail "the callback did not see the open: $(echo "$output" | grep -F 'fsnotify allow test')"
ktap_pass "the open the callback allowed is the one it was asked about"

errs=$(echo "$output" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

