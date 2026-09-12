#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# FS_OPEN_EXEC_PERM gates the exec of a file and not a read of it.
#
# The mark carries the exec permission event and nothing else, so the same file
# is refused to execve and handed over to cat: what separates the two is the
# __FMODE_EXEC the exec path sets, which fsnotify_open_perm turns into
# FS_OPEN_EXEC_PERM before the FS_OPEN_PERM this mark is not placed for. The
# program is a copy of a system binary made on the test's own tmpfs, so the deny
# reaches nothing else, and the last case executes it again once the watch is
# stopped.
#
# Usage: sudo bash tests/fsnotify/exec.sh

SCRIPT="tests/fsnotify/exec"

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

perm_begin 6 "fsnotify/exec"

cp /bin/true "$MOUNT/prog" || fail "could not copy a program onto the tmpfs"

"$MOUNT/prog" || fail "the copied program does not run before anything marks it"

mark_dmesg
run_script "$SCRIPT"
refused=$("$MOUNT/prog" 2>&1)
status=$?
content=$(cat "$MOUNT/prog" > /dev/null 2>&1; echo $?)
output=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null
"$MOUNT/prog"
again=$?

[ "$status" -ne 0 ] || fail "the denied exec succeeded"
ktap_pass "a callback returning DENY fails the exec"

echo "$refused" | grep -qi "not permitted" || fail "the denied exec failed with: $refused"
ktap_pass "the denied exec fails with EPERM"

[ "$content" -eq 0 ] || fail "reading the program failed too (exit $content)"
ktap_pass "a mark for FS_OPEN_EXEC_PERM does not gate an ordinary read"

echo "$output" | grep -qF "exec test: $MOUNT/prog mask 40000" || \
	fail "the callback did not see the exec: $(echo "$output" | grep -F 'fsnotify exec test')"
ktap_pass "the event the callback denied is FS_OPEN_EXEC_PERM"

[ "$again" -eq 0 ] || fail "the program did not run after the watch stopped (exit $again)"
ktap_pass "the denial ends with the watch that made it"

errs=$(echo "$output" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

