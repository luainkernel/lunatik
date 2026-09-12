#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The fsmonitor example reports what changed in the directory it watches.
#
# The example is the kernel-side script here, run from where examples_install
# puts it, so this test covers what a reader of the README gets rather than a
# copy of it. The stimuli are the four events it names, driven in the directory
# its WATCHED constant points at, and the two the shell performs itself are
# matched by its own pid. The subdirectory case is the other half: EVENT_ON_CHILD
# reaches the entries of the marked directory and no deeper, so the subdirectory's
# own creation is reported and the file created inside it is not.
#
# Usage: sudo bash tests/fsnotify/fsmonitor.sh

SCRIPT="examples/fsmonitor"
WATCHED="/tmp/lunatik-fsmonitor"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -rf "$WATCHED"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$WATCHED"

ktap_header
ktap_plan 8

mark_dmesg
run_script "$SCRIPT"

: > "$WATCHED/file"
fileino=$(stat -c %i "$WATCHED/file")
echo data > "$WATCHED/file"
chmod 600 "$WATCHED/file"
mkdir "$WATCHED/sub"
subino=$(stat -c %i "$WATCHED/sub")
: > "$WATCHED/sub/deep"
rm -f "$WATCHED/file"
output=$(dmesg_since)

lunatik stop "$SCRIPT" 2>/dev/null

mark_dmesg
: > "$WATCHED/after"
quiet=$(dmesg_since)

grep -qF "fsmonitor: created file ino $fileino pid $$" <<< "$output" || \
	fail "the create was not reported: $(grep -F 'fsmonitor:' <<< "$output")"
ktap_pass "a created entry is reported with its name, inode and the pid that made it"

grep -qF "fsmonitor: modified file ino $fileino pid $$" <<< "$output" || \
	fail "the write was not reported: $(grep -F 'fsmonitor:' <<< "$output")"
ktap_pass "a write to a file in the directory is reported"

grep -qE "fsmonitor: attributes file ino $fileino pid [0-9]+" <<< "$output" || \
	fail "the chmod was not reported: $(grep -F 'fsmonitor:' <<< "$output")"
ktap_pass "an attribute change is reported"

grep -qE "fsmonitor: deleted file ino $fileino pid [0-9]+" <<< "$output" || \
	fail "the unlink was not reported: $(grep -F 'fsmonitor:' <<< "$output")"
ktap_pass "a deleted entry is reported, still carrying its inode"

grep -qE "fsmonitor: created sub ino $subino pid [0-9]+" <<< "$output" || \
	fail "the subdirectory's creation was not reported: $(grep -F 'fsmonitor:' <<< "$output")"
ktap_pass "a subdirectory created in the watched directory is reported"

grep -q "fsmonitor: .* deep " <<< "$output" && \
	fail "a file created below the watched directory was reported: $(grep -F 'deep' <<< "$output")"
ktap_pass "nothing below the watched directory is reported"

grep -q "fsmonitor:" <<< "$quiet" && \
	fail "the example still reported after it was stopped: $(grep -F 'fsmonitor:' <<< "$quiet")"
ktap_pass "the example stops reporting when it is stopped"

errs=$(printf '%s\n' "$output" "$quiet" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

