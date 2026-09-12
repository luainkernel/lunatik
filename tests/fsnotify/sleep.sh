#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A callback that sleeps finishes, and the syscall waits for it.
#
# This is what makes a process-context runtime the right one: the callback runs
# on the task performing the access, which is inside its own open syscall, so it
# may schedule out and the open resumes when it comes back. The shell times the
# open around linux.schedule(300) and asserts both halves, that it took the nap
# and that it returned the file's content, since an open that never waited and
# one that never returned are different failures. The callback's own line is
# asserted too: a loaded host can take the nap without one.
#
# Usage: sudo bash tests/fsnotify/sleep.sh

SCRIPT="tests/fsnotify/sleep"
NAP=300

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

perm_begin 4 "fsnotify/sleep"

echo content > "$MOUNT/gated"

mark_dmesg
run_script "$SCRIPT"
started=$(date +%s%N)
content=$(timeout 30 cat "$MOUNT/gated" 2>&1)
elapsed=$(( ($(date +%s%N) - started) / 1000000 ))
output=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null

[ "$content" = content ] || fail "the open the sleeping callback allowed did not return: $content"
ktap_pass "an open a sleeping callback allows returns its content"

[ "$elapsed" -ge "$NAP" ] || fail "the open took ${elapsed}ms, less than the ${NAP}ms the callback slept"
ktap_pass "the open waits for the callback that slept"

echo "$output" | grep -qF "sleep test: $MOUNT/gated mask 10000" || \
	fail "the callback did not see the open: $(echo "$output" | grep -F 'fsnotify sleep test')"
ktap_pass "the open that waited is the one the callback was asked about"

errs=$(echo "$output" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

