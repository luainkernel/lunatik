#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A mark whose path is gone when its mask is set: the re-add raises ENOENT and
# leaves the handle dead.
#
# mark:mask removes the mark and adds it again from the path it was placed
# with, so a path that no longer resolves fails the add after the removal. The
# call comes from outside a callback: from one, the walk stays in the directory
# cache, where a rename leaves no dentry under the old name, so it answers
# EAGAIN, or ENOENT only once a later lookup left a negative dentry the
# filesystem kept. vanished.lua therefore makes the call from the read handler
# of a device it creates, which runs in the shell's own read, in the script's
# runtime, after the shell moved the file.
#
# The file is moved rather than unlinked, so the inode the mark was on stays and
# the shell opens it afterwards: a mark the failed re-add left in place would
# deliver that open.
#
# Usage: sudo bash tests/fsnotify/vanished.sh

SCRIPT="tests/fsnotify/vanished"
SCRATCH="/tmp/lunatik-fsnotify"
TRIGGER="/dev/fsnotify_vanished"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/vanished"

ktap_header
ktap_plan 4

mark_dmesg
run_script "$SCRIPT"
[ -c "$TRIGGER" ] || fail "the script's device $TRIGGER did not appear"
mv "$SCRATCH/vanished" "$SCRATCH/moved"
cat "$TRIGGER" > /dev/null
cat "$SCRATCH/moved" > /dev/null
output=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null

echo "$output" | grep -qF "fsnotify vanished test pass: mask raises ENOENT once the path is gone" || \
	fail "the re-add of a path that is gone: $(echo "$output" | grep -F 'fsnotify vanished test' | tr '\n' ';')"
ktap_pass "mask raises ENOENT when the path it re-adds from is gone"

echo "$output" | grep -qF "fsnotify vanished test pass: the handle is dead after the failed re-add" || \
	fail "the handle after the failed re-add: $(echo "$output" | grep -F 'fsnotify vanished test' | tr '\n' ';')"
ktap_pass "the handle is dead after the failed re-add"

echo "$output" | grep -qF "fsnotify vanished test pass: the watch no longer marks the moved inode" || \
	fail "the watch after the failed re-add: $(echo "$output" | grep -F 'fsnotify vanished test' | tr '\n' ';')"
echo "$output" | grep -qF "fsnotify vanished test fail: event" && \
	fail "the inode still delivered after the failed re-add: $(echo "$output" | grep -F 'fail: event')"
ktap_pass "the failed re-add leaves the inode unmarked"

errs=$(echo "$output" | grep -E "$KTAP_ERRORS" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals

