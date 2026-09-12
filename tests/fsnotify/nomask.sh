#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# An event outside the mark's mask does not reach the callback.
#
# The kernel script marks $SCRATCH/watched for FS_MODIFY alone. Reading the file
# is an FS_OPEN and must deliver nothing; writing to it is an FS_MODIFY and must
# deliver, which is what keeps the negative half from passing on a dead watch.
#
# Usage: sudo bash tests/fsnotify/nomask.sh

SCRIPT="tests/fsnotify/nomask"
SCRATCH="/tmp/lunatik-fsnotify"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/watched"

ktap_header
ktap_plan 3

mark_dmesg
run_script "$SCRIPT"

cat "$SCRATCH/watched" > /dev/null
unmasked=$(dmesg_since)

mark_dmesg
echo lunatik >> "$SCRATCH/watched"
masked=$(dmesg_since)

lunatik stop "$SCRIPT" 2>/dev/null

echo "$unmasked" | grep -qF "fsnotify nomask test" && \
	fail "FS_OPEN reached a callback whose mark asks for FS_MODIFY"
ktap_pass "an event outside the mark's mask does not reach the callback"

echo "$masked" | grep -qF "fsnotify nomask test pass" || \
	fail "no FS_MODIFY for the marked file: $(echo "$masked" | grep -F 'fsnotify nomask test')"
ktap_pass "an event inside the mark's mask still reaches the callback"

errs=$(printf '%s\n%s\n' "$unmasked" "$masked" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

