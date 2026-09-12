#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The three kinds of mark, on a filesystem the test brings with it.
#
# A mount and a superblock mark reach every file they cover, so this test
# creates its own tmpfs under the scratch directory and marks that, never a
# filesystem the machine needs; it skips if the mount does not appear. The same
# tmpfs is bind mounted a second time, which is what separates the two kinds: a
# mount mark sees only the mount it was placed on, while a superblock mark sees
# the same inode opened through either.
#
# wide.lua then asks the watch for each of its three marks back, by path and
# kind, and leaves them installed when it returns; the shell unmounts under
# them before stopping the script: the kernel clears the marks of a mount it
# is destroying, and the watch's teardown has to walk them anyway.
#
# Usage: sudo bash tests/fsnotify/kinds.sh

SCRIPT="tests/fsnotify/mount"
SB="tests/fsnotify/sb"
WIDE="tests/fsnotify/wide"
SCRATCH="/tmp/lunatik-fsnotify"
MOUNT="$SCRATCH/mnt"
BIND="$SCRATCH/bind"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$SB" 2>/dev/null
	lunatik stop "$WIDE" 2>/dev/null
	umount "$BIND" 2>/dev/null
	umount "$MOUNT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 9

mkdir -p -m 0700 "$MOUNT" "$BIND"
: > "$SCRATCH/outside"

if ! mount -t tmpfs -o size=1M,mode=0700 lunatik-fsnotify "$MOUNT" 2>/dev/null || \
	! mountpoint -q "$MOUNT"; then
	for _ in $(seq 9); do ktap_skip "fsnotify/kinds: no tmpfs to mark"; done
	ktap_totals
	exit 0
fi

mkdir -p "$MOUNT/sub"
: > "$MOUNT/sub/inside"

bound=yes
mount --bind "$MOUNT" "$BIND" 2>/dev/null || bound=no

mark_dmesg
run_script "$SCRIPT"
cat "$MOUNT/sub/inside" > /dev/null
cat "$SCRATCH/outside" > /dev/null
[ "$bound" = yes ] && cat "$BIND/sub/inside" > /dev/null
mounted=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null

mark_dmesg
run_script "$SB"
[ "$bound" = yes ] && cat "$BIND/sub/inside" > /dev/null
cat "$SCRATCH/outside" > /dev/null
super=$(dmesg_since)
lunatik stop "$SB" 2>/dev/null

mark_dmesg
run_script "$WIDE"
umount "$BIND" 2>/dev/null
umount "$MOUNT" || fail "the tmpfs stayed busy while marked"
lunatik stop "$WIDE" 2>/dev/null
unmounted=$(dmesg_since)

echo "$mounted" | grep -qF "mount open $MOUNT/sub/inside" || \
	fail "no event for a file under the marked mount: $(echo "$mounted" | grep -F 'fsnotify kinds test')"
ktap_pass "a mount mark reports a file opened under its mount"

echo "$mounted" | grep -qF "mount open $SCRATCH/outside" && \
	fail "a mount mark reported a file outside its mount"
ktap_pass "a mount mark reports nothing outside its mount"

if [ "$bound" = yes ]; then
	echo "$mounted" | grep -qF "mount open $BIND/sub/inside" && \
		fail "a mount mark reported an open through another mount"
	ktap_pass "a mount mark reports nothing through another mount of the same filesystem"

	echo "$super" | grep -qF "sb open $BIND/sub/inside" || \
		fail "no event for a file opened through another mount: $(echo "$super" | grep -F 'fsnotify kinds test')"
	ktap_pass "a superblock mark reports a file opened through another mount"
else
	ktap_skip "a mount mark reports nothing through another mount of the same filesystem: no bind mount"
	ktap_skip "a superblock mark reports a file opened through another mount: no bind mount"
fi

echo "$super" | grep -qF "sb open $SCRATCH/outside" && \
	fail "a superblock mark reported a file on another filesystem"
ktap_pass "a superblock mark reports nothing on another filesystem"

echo "$mounted" | grep -qF "fsnotify kinds test pass: an invalid kind" || \
	fail "the invalid kind was not refused: $(echo "$mounted" | grep -F 'fsnotify kinds test')"
ktap_pass "an invalid kind raises naming the valid ones"

found=$(echo "$unmounted" | grep -cF "fsnotify kinds test pass: find")
[ "$found" -eq 4 ] || \
	fail "find by kind: $(echo "$unmounted" | grep -F 'fsnotify kinds test' | tr '\n' ';')"
ktap_pass "find returns the mark of each kind, and nil for a kind not marked"

oops=$(printf '%s\n%s\n%s\n' "$mounted" "$super" "$unmounted" | \
	grep -E "Oops:|BUG:|kernel BUG at|NULL pointer dereference|general protection" || true)
[ -n "$oops" ] && fail "kernel error with mount and superblock marks: ${oops%%$'\n'*}"
ktap_pass "unmounting under an inode, a mount and a superblock mark raises no kernel error"

errs=$(printf '%s\n%s\n%s\n' "$mounted" "$super" "$unmounted" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

