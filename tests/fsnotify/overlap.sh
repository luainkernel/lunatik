#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# An event matched by two marks of one watch is delivered once.
#
# The watch dispatches through the group's handle_event, which the kernel calls
# once per group with the event as raised, rather than once per matching mark
# the way handle_inode_event is called. overlap.lua marks $SCRATCH/watched for
# FS_OPEN and $SCRATCH for FS_OPEN | FS_EVENT_ON_CHILD in the same watch, so an
# open of the file matches both: it must reach the callback exactly once,
# tagged FS_EVENT_ON_CHILD and carrying the entry's name and directory, not once
# without the name for the file's mark and once with it for the directory's.
# Opening the directory itself matches one mark and must still arrive once.
#
# The lines are selected by this shell's pid, so another process opening the
# scratch file in the window cannot be counted as a second delivery.
#
# Usage: sudo bash tests/fsnotify/overlap.sh

SCRIPT="tests/fsnotify/overlap"
SCRATCH="/tmp/lunatik-fsnotify"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

# the lines the events of one mask printed for this shell
rows() { grep -F "fsnotify overlap test note: mask=$2 " <<< "$1" | grep -E " pid=$$\$"; }

check() {
	local got
	got=$(sed -n "s/.* $2=\([^ ]*\).*/\1/p" <<< "$1")
	[ "$got" = "$3" ] || fail "$4: $2 = '$got', expected '$3'"
}

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/watched"

dirino=$(stat -c %i "$SCRATCH")
fileino=$(stat -c %i "$SCRATCH/watched")

ktap_header
ktap_plan 3

mark_dmesg
run_script "$SCRIPT"

exec 3< "$SCRATCH/watched"
exec 3<&-
opened=$(dmesg_since)
lines=$(rows "$opened" 8000020)
count=$(grep -c . <<< "$lines")
[ "$count" -eq 1 ] || fail "a file matched by two marks was delivered $count times: $(rows "$opened" 20)"
check "$lines" name watched "a file open"
check "$lines" ino "$fileino" "a file open"
check "$lines" dir "$dirino" "a file open"
ktap_pass "a file marked with its parent arrives once, tagged FS_EVENT_ON_CHILD with its name"

mark_dmesg
exec 3< "$SCRATCH"
exec 3<&-
listed=$(dmesg_since)
count=$(rows "$listed" 40000020 | grep -c .)
[ "$count" -eq 1 ] || fail "the marked directory's own open was delivered $count times"
ktap_pass "the directory's own open arrives once"

lunatik stop "$SCRIPT" 2>/dev/null

errs=$(printf '%s\n%s\n' "$opened" "$listed" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

