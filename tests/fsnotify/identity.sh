#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# What the event handed to a callback knows about itself, over the matrix of
# event kind by accessor.
#
# The kernel attaches a different thing to each kind of event, and that is what
# decides which accessor can answer: an event raised from an open file carries a
# struct path, so name, ino, dir, isdir, pid and path all answer; a directory
# entry event carries only the entry's dentry or inode, so path is nil. Both
# halves matter, so each case asserts every accessor, the nil ones included.
#
# identity.lua marks $SCRATCH/watched for FS_OPEN and $SCRATCH for FS_OPEN plus
# the four directory entry events, and prints one line per event carrying all
# six. The shell drives one stimulus per case and reads the fields back against
# what it already knows: stat -c %i for the inode numbers, its own $$ for the
# pid, and the path it built.
#
# For a stimulus this shell performs itself the line is selected by that pid, so
# another process opening the same scratch file in the window cannot be read as
# ours.
#
# Three events need marks of their own. $SCRATCH/from is marked for FS_RENAME,
# which the kernel reports on the old directory with the old name and the moved
# dentry; the binding takes it through handle_event, which has no same-parent
# filter, so a move out of the directory arrives as a move within it does. A
# file the shell holds open, unlinks and then writes to reports a path d_path
# renders with a trailing " (deleted)". A file whose directory the shell buries
# under names of NAME_MAX bytes, one level at a time so that no path it passes
# nears PATH_MAX, reports a write through a descriptor opened before the burial,
# and its path no longer fits the PATH_MAX buffer d_path fills: event:path()
# raises ENAMETOOLONG, which identity.lua prints in place of the path.
#
# Usage: sudo bash tests/fsnotify/identity.sh

SCRIPT="tests/fsnotify/identity"
SCRATCH="/tmp/lunatik-fsnotify"
PATH_MAX=4096
NAME_MAX=255

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

# the line one event printed: its mask, and optionally the pid that caused it
row() { grep -F "fsnotify identity: mask=$2 " <<< "$1" | grep -F "${3:+ pid=$3 }" | head -1; }

check() {
	local got
	got=$(sed -n "s/.* $2=\([^ ]*\).*/\1/p" <<< "$1")
	[ "$got" = "$3" ] || fail "$4: $2 = '$got', expected '$3'"
}

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/watched"
mkdir -p "$SCRATCH/from" "$SCRATCH/to" "$SCRATCH/pit/sunk"
: > "$SCRATCH/from/before"
: > "$SCRATCH/gone"
: > "$SCRATCH/pit/sunk/buried"

dirino=$(stat -c %i "$SCRATCH")
fileino=$(stat -c %i "$SCRATCH/watched")
fromino=$(stat -c %i "$SCRATCH/from")
movedino=$(stat -c %i "$SCRATCH/from/before")
goneino=$(stat -c %i "$SCRATCH/gone")
buriedino=$(stat -c %i "$SCRATCH/pit/sunk/buried")

ktap_header
ktap_plan 10

mark_dmesg
run_script "$SCRIPT"

exec 3< "$SCRATCH/watched"
exec 3<&-
opened=$(dmesg_since)
line=$(row "$opened" 20 "$$")
[ -n "$line" ] || fail "no FS_OPEN for the marked file"
check "$line" name nil "a file open"
check "$line" ino "$fileino" "a file open"
check "$line" dir nil "a file open"
check "$line" isdir false "a file open"
check "$line" path "$SCRATCH/watched" "a file open"
ktap_pass "a file event carries an inode and a path, and no directory entry"

mark_dmesg
ls "$SCRATCH" > /dev/null
listed=$(dmesg_since)
line=$(row "$listed" 40000020)
[ -n "$line" ] || fail "no FS_OPEN | FS_ISDIR for the marked directory"
check "$line" name nil "a directory open"
check "$line" ino "$dirino" "a directory open"
check "$line" dir nil "a directory open"
check "$line" isdir true "a directory open"
check "$line" path "$SCRATCH" "a directory open"
ktap_pass "a directory event is flagged FS_ISDIR and carries the directory's path"

mark_dmesg
: > "$SCRATCH/created"
created=$(dmesg_since)
line=$(row "$created" 100 "$$")
createdino=$(stat -c %i "$SCRATCH/created")
[ -n "$line" ] || fail "no FS_CREATE for the marked directory"
check "$line" name created "a create"
check "$line" ino "$createdino" "a create"
check "$line" dir "$dirino" "a create"
check "$line" isdir false "a create"
check "$line" path nil "a create"
ktap_pass "a create names the entry and its directory, and carries no path"

mark_dmesg
mv "$SCRATCH/created" "$SCRATCH/moved"
moves=$(dmesg_since)
from=$(row "$moves" 40)
to=$(row "$moves" 80)
[ -n "$from" ] && [ -n "$to" ] || fail "a rename delivered '$from' and '$to'"
check "$from" name created "a moved_from"
check "$from" ino "$createdino" "a moved_from"
check "$from" dir "$dirino" "a moved_from"
check "$from" path nil "a moved_from"
check "$to" name moved "a moved_to"
check "$to" ino "$createdino" "a moved_to"
check "$to" dir "$dirino" "a moved_to"
check "$to" path nil "a moved_to"
ktap_pass "a rename names the old entry and the new one for the same inode"

mark_dmesg
rm -f "$SCRATCH/moved"
deleted=$(dmesg_since)
line=$(row "$deleted" 200)
[ -n "$line" ] || fail "no FS_DELETE for the marked directory"
check "$line" name moved "a delete"
check "$line" ino "$createdino" "a delete"
check "$line" dir "$dirino" "a delete"
check "$line" isdir false "a delete"
check "$line" path nil "a delete"
ktap_pass "a delete still names the unlinked entry and its inode"

mark_dmesg
mv "$SCRATCH/from/before" "$SCRATCH/from/renamed"
within=$(dmesg_since)
line=$(row "$within" 10000000)
[ -n "$line" ] || fail "no FS_RENAME for a move within the marked directory"
check "$line" name before "a rename within a directory"
check "$line" ino "$movedino" "a rename within a directory"
check "$line" dir "$fromino" "a rename within a directory"
check "$line" isdir false "a rename within a directory"
check "$line" path nil "a rename within a directory"
ktap_pass "FS_RENAME names the old entry, its directory and the moved inode"

mark_dmesg
mv "$SCRATCH/from/renamed" "$SCRATCH/to/moved"
across=$(dmesg_since)
line=$(row "$across" 10000000)
[ -n "$line" ] || fail "no FS_RENAME for a move out of the marked directory"
check "$line" name renamed "a rename across directories"
check "$line" ino "$movedino" "a rename across directories"
check "$line" dir "$fromino" "a rename across directories"
check "$line" isdir false "a rename across directories"
check "$line" path nil "a rename across directories"
ktap_pass "FS_RENAME arrives for a move across directories too"

mark_dmesg
exec 3>> "$SCRATCH/gone"
rm -f "$SCRATCH/gone"
echo gone >&3
exec 3>&-
unlinked=$(dmesg_since)
line=$(row "$unlinked" 2 "$$")
[ -n "$line" ] || fail "no FS_MODIFY for the unlinked file"
check "$line" name nil "a write to an unlinked file"
check "$line" ino "$goneino" "a write to an unlinked file"
check "$line" dir nil "a write to an unlinked file"
check "$line" isdir false "a write to an unlinked file"
[[ "$line" == *" path=$SCRATCH/gone (deleted)" ]] || \
	fail "a write to an unlinked file: path = '${line##* path=}', expected '$SCRATCH/gone (deleted)'"
ktap_pass "the path of an unlinked file carries a trailing (deleted)"

long=$(printf "%${NAME_MAX}s" "" | tr ' ' x)
exec 4>> "$SCRATCH/pit/sunk/buried"
for _ in $(seq $((PATH_MAX / (NAME_MAX + 1) + 1))); do
	mkdir "$SCRATCH/pit/wrap" && mv "$SCRATCH/pit/sunk" "$SCRATCH/pit/wrap/$long" && \
		mv "$SCRATCH/pit/wrap" "$SCRATCH/pit/sunk" || fail "could not bury the marked file"
done
mark_dmesg
echo buried >&4
exec 4>&-
buried=$(dmesg_since)
line=$(row "$buried" 2 "$$")
[ -n "$line" ] || fail "no FS_MODIFY for the buried file"
check "$line" ino "$buriedino" "a write to a file past PATH_MAX"
check "$line" path raised:ENAMETOOLONG "a write to a file past PATH_MAX"
ktap_pass "the path of a file past PATH_MAX raises ENAMETOOLONG"

lunatik stop "$SCRIPT" 2>/dev/null

errs=$(printf '%s\n' "$opened" "$listed" "$created" "$moves" "$deleted" "$within" "$across" "$unlinked" "$buried" | \
	grep -E "$KTAP_ERRORS" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

