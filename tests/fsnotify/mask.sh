#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A live mark's masks: the event mask, and the ignore mask.
#
# mask.lua places a mark for FS_OPEN and then sets it to FS_MODIFY, so the
# shell's read of that file must deliver nothing and its write must deliver
# FS_MODIFY: the event the mark was added with is gone, and the one added
# afterwards arrives, which is what tells a recalculated object mask from a
# field written on the mark alone.
#
# The second mark carries both events and ignores FS_OPEN, so the read is
# silent while the write still arrives: the ignore mask must suppress what it
# names and nothing else. A read after that write must be silent too: the
# kernel clears a mark's ignore mask on every FS_MODIFY unless the mark asks
# to keep it, and only the read that follows the write tells the two apart.
#
# Usage: sudo bash tests/fsnotify/mask.sh

SCRIPT="tests/fsnotify/mask"
SCRATCH="/tmp/lunatik-fsnotify"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/widened"
: > "$SCRATCH/ignored"

ktap_header
ktap_plan 7

mark_dmesg
run_script "$SCRIPT"

cat "$SCRATCH/widened" > /dev/null
cat "$SCRATCH/ignored" > /dev/null
opened=$(dmesg_since)

mark_dmesg
echo written > "$SCRATCH/widened"
echo written > "$SCRATCH/ignored"
written=$(dmesg_since)

mark_dmesg
cat "$SCRATCH/ignored" > /dev/null
reopened=$(dmesg_since)

lunatik stop "$SCRIPT" 2>/dev/null

checks=$(echo "$opened" | grep -cF "fsnotify mask test pass:")
[ "$checks" -eq 4 ] || \
	fail "the mask accessors: $(echo "$opened" | grep -F 'fsnotify mask test' | tr '\n' ';')"
ktap_pass "mask and ignore read back what they were set to"

echo "$opened" | grep -qF "mask test: $SCRATCH/widened" && \
	fail "an event removed from a live mark still arrived"
ktap_pass "an event set out of a live mark's mask stops arriving"

echo "$written" | grep -qF "mask test: $SCRATCH/widened mask 2" || \
	fail "no FS_MODIFY for the widened mark: $(echo "$written" | grep -F 'fsnotify mask test')"
ktap_pass "an event set into a live mark's mask arrives"

echo "$opened" | grep -qF "mask test: $SCRATCH/ignored" && \
	fail "an ignored event still arrived"
ktap_pass "an ignored event is not reported"

echo "$written" | grep -qF "mask test: $SCRATCH/ignored mask 2" || \
	fail "no FS_MODIFY for the ignoring mark: $(echo "$written" | grep -F 'fsnotify mask test')"
ktap_pass "an ignore mask suppresses what it names and nothing else"

echo "$reopened" | grep -qF "mask test: $SCRATCH/ignored" && \
	fail "a write cleared the ignore mask"
ktap_pass "an ignore mask survives a write to the object"

errs=$(printf '%s\n%s\n%s\n' "$opened" "$written" "$reopened" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

