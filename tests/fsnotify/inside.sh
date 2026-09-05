#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A mark removed, and a mark's mask changed, from inside the callback.
#
# The callback runs inside fsnotify's SRCU read section, and both operations
# take the group's mark mutex there; inotify's one-shot watch destroys its mark
# from the same place, so the path is the kernel's own. inside.lua removes the
# oneshot mark on its first event and sets the remasked mark from FS_OPEN to
# FS_MODIFY on its first event, so the shell's second read of each must be
# silent, and its write to the second must arrive.
#
# Both operations resolve a path, and the task the callback runs on may hold the
# lock of the directory the event is about, so from a callback the walk stays in
# the directory cache. inside.lua asks for a name the shell never touches, which
# is therefore not cached: it answers EAGAIN rather than descending into a lock
# its own task may hold. The two paths it does resolve are cached, which is why
# the operations above still work.
#
# Usage: sudo bash tests/fsnotify/inside.sh

SCRIPT="tests/fsnotify/inside"
SCRATCH="/tmp/lunatik-fsnotify"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/oneshot"
: > "$SCRATCH/remasked"

ktap_header
ktap_plan 6

mark_dmesg
run_script "$SCRIPT"
cat "$SCRATCH/oneshot" > /dev/null
cat "$SCRATCH/oneshot" > /dev/null
oneshot=$(dmesg_since)

mark_dmesg
cat "$SCRATCH/remasked" > /dev/null
cat "$SCRATCH/remasked" > /dev/null
opened=$(dmesg_since)

mark_dmesg
echo written > "$SCRATCH/remasked"
written=$(dmesg_since)

lunatik stop "$SCRIPT" 2>/dev/null

seen=$(echo "$oneshot" | grep -cF "inside test: $SCRATCH/oneshot")
[ "$seen" -eq 1 ] || fail "the oneshot mark delivered $seen events, expected 1"
ktap_pass "a mark removed from inside its callback delivers once"

seen=$(echo "$opened" | grep -cF "inside test: $SCRATCH/remasked mask 20")
[ "$seen" -eq 1 ] || fail "the remasked mark delivered $seen opens, expected 1"
ktap_pass "a mark set from inside its callback delivers the event it was placed for once"

echo "$written" | grep -qF "inside test: $SCRATCH/remasked mask 2" || \
	fail "no FS_MODIFY after the mask was set from the callback: $(echo "$written" | grep -F 'fsnotify inside test')"
ktap_pass "a mark set from inside its callback delivers the event it was set to"

echo "$written" | grep -qF "inside test: $SCRATCH/remasked mask 20" && \
	fail "the event set out of the mask from the callback still arrived"
ktap_pass "a mark set from inside its callback stops delivering the event it was set out of"

echo "$oneshot" | grep -qF "inside test: uncached EAGAIN" || \
	fail "a path outside the directory cache did not answer EAGAIN: $(echo "$oneshot" | grep -F 'inside test: uncached')"
ktap_pass "a path resolved from inside a callback stays in the directory cache"

errs=$(printf '%s\n%s\n%s\n' "$oneshot" "$opened" "$written" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

