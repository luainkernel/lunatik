#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A callback that raises leaves the access allowed, and says so in the log.
#
# The access is decided either way, and the only answer a callback that did not
# finish can be given is the one that takes nothing away: the raise reaches the
# pcall, the message is logged and the verdict stays what the handler started
# with. The second open shows the watch is still there afterwards rather than
# having been torn down by the error, which would make the first case pass for
# the wrong reason.
#
# This is the one test in the suite whose kernel log carries a Lua error on
# purpose, so it asserts on that message instead of asserting there is none.
#
# Usage: sudo bash tests/fsnotify/error.sh

SCRIPT="tests/fsnotify/error"

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

perm_begin 3 "fsnotify/error"

echo content > "$MOUNT/gated"

mark_dmesg
run_script "$SCRIPT"
first=$(cat "$MOUNT/gated" 2>&1)
raised=$(dmesg_since)

mark_dmesg
second=$(cat "$MOUNT/gated" 2>&1)
again=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null

[ "$first" = content ] || fail "the open a raising callback was asked about failed: $first"
ktap_pass "a callback that raises allows the access"

echo "$raised" | grep -qE "error\.lua:[0-9]+: the guard raised" || \
	fail "the raise was not logged: $(echo "$raised" | grep -F 'error.lua')"
ktap_pass "the error the callback raised is logged"

[ "$second" = content ] || fail "the second open failed: $second"
echo "$again" | grep -qF "error test: $MOUNT/gated mask 10000" || \
	fail "the watch stopped delivering after the raise: $(echo "$again" | grep -F 'fsnotify error test')"
ktap_pass "the watch keeps delivering and allowing after a raise"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

