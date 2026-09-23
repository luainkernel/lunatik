#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A mark removed, a mark's mask changed, marks placed, and a watch stopped, from
# inside the callback.
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
# The open events above arrive with no directory lock held, so the last case
# marks the scratch directory for FS_CREATE, which the kernel delivers inside
# the parent's i_rwsem, and resolves the uncached name from that callback: it
# answers EAGAIN there too. A tree without the flag wedges the host on this
# case, since the walk takes the lock its own task holds, so it runs only on a
# tree that carries the flag and discriminates by the message, never by an A/B.
#
# The resolver's open, delivered with no directory lock held, places marks from
# the callback: the cached name the shell created resolves, and its later open
# arrives through the new mark, while the name the shell never touches answers
# EAGAIN as find does. The flag that keeps the walk in the cache belongs to the
# runtime, not to the watch, so another watch of the same runtime asked from
# the first watch's callback answers EAGAIN for that name too, and still finds
# its own mark on a cached one.
#
# The moved file is renamed by the shell before its open, which leaves the name
# its mark was placed with out of the directory cache, so setting its mask from
# the callback resolves that name again and answers EAGAIN; the mark it removed
# first stays removed, and the second open is silent.
#
# The halted file has a watch of its own in the same runtime, which stops itself
# from its callback. The stop removes every mark of its group inside that read
# section too, and detaches the event object the dispatcher still holds, so the
# call must return, the shell's second read of the halted file must be silent,
# and the runtime must still tear down cleanly when the shell stops it.
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
: > "$SCRATCH/resolver"
: > "$SCRATCH/marked"
: > "$SCRATCH/other"
: > "$SCRATCH/halted"
: > "$SCRATCH/moved"

ktap_header
ktap_plan 14

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

mark_dmesg
: > "$SCRATCH/created"
created=$(dmesg_since)

mark_dmesg
cat "$SCRATCH/resolver" > /dev/null
resolved=$(dmesg_since)

mark_dmesg
cat "$SCRATCH/marked" > /dev/null
marked=$(dmesg_since)

mark_dmesg
mv "$SCRATCH/moved" "$SCRATCH/renamed"
cat "$SCRATCH/renamed" > /dev/null
cat "$SCRATCH/renamed" > /dev/null
moved=$(dmesg_since)

mark_dmesg
cat "$SCRATCH/halted" > /dev/null
cat "$SCRATCH/halted" > /dev/null
halted=$(dmesg_since)

mark_dmesg
lunatik stop "$SCRIPT" 2>/dev/null
stopped=$(dmesg_since)
listed=$(lunatik list)

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

echo "$created" | grep -qF "inside test: locked EAGAIN" || \
	fail "a path resolved under the directory lock did not answer EAGAIN: $(echo "$created" | grep -F 'inside test: locked')"
ktap_pass "a path resolved from a callback under the directory lock stays in the directory cache"

echo "$resolved" | grep -qF "inside test: mark cached resolved" || \
	fail "a cached path marked from the callback did not resolve: $(echo "$resolved" | grep -F 'inside test: mark')"
seen=$(echo "$marked" | grep -cF "inside test: $SCRATCH/marked mask 20")
[ "$seen" -eq 1 ] || fail "the mark placed from the callback delivered $seen opens, expected 1"
ktap_pass "a mark placed from inside a callback on a cached path delivers"

echo "$resolved" | grep -qF "inside test: mark uncached EAGAIN" || \
	fail "an uncached path marked from the callback did not answer EAGAIN: $(echo "$resolved" | grep -F 'inside test: mark')"
ktap_pass "a mark placed from inside a callback stays in the directory cache"

echo "$resolved" | grep -qF "inside test: other uncached EAGAIN" || \
	fail "a second watch resolving from the first's callback left the cache: $(echo "$resolved" | grep -F 'inside test: other')"
echo "$resolved" | grep -qF "inside test: other cached resolved" || \
	fail "a second watch did not find its mark from the first's callback: $(echo "$resolved" | grep -F 'inside test: other')"
ktap_pass "a second watch of the runtime resolves from the first watch's callback within the directory cache"

echo "$moved" | grep -qF "inside test: remask moved EAGAIN" || \
	fail "a renamed path set from the callback did not answer EAGAIN: $(echo "$moved" | grep -F 'inside test: remask')"
seen=$(echo "$moved" | grep -cF "inside test: $SCRATCH/renamed mask 20")
[ "$seen" -eq 1 ] || fail "the mark whose path no longer resolved delivered $seen opens, expected 1"
ktap_pass "a mask set from inside a callback on a renamed path answers EAGAIN and leaves the mark removed"

seen=$(echo "$halted" | grep -cF "inside test: stop returned")
[ "$seen" -eq 1 ] || fail "stop from inside the callback returned $seen times, expected 1: $(echo "$halted" | grep -F 'fsnotify inside test')"
ktap_pass "a watch stopped from inside its callback returns from stop"

seen=$(echo "$halted" | grep -cF "inside test: halting on $SCRATCH/halted")
[ "$seen" -eq 1 ] || fail "the watch stopped from its callback delivered $seen events, expected 1"
ktap_pass "a watch stopped from inside its callback delivers nothing afterwards"

case "$listed" in
	*"$SCRIPT"*) fail "the runtime whose watch stopped itself is still listed: $listed" ;;
esac
errs=$(echo "$stopped" | grep -E "$KTAP_ERRORS" || true)
[ -n "$errs" ] && fail "kernel error stopping the runtime whose watch stopped itself: ${errs%%$'\n'*}"
ktap_pass "the runtime whose watch stopped itself tears down cleanly"

errs=$(printf '%s\n' "$oneshot" "$opened" "$written" "$created" "$resolved" "$marked" "$moved" "$halted" | \
	grep -E "$KTAP_ERRORS" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals

