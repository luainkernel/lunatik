#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# An event kept past the callback it was handed to raises when read.
#
# The event object is reused for every event of the watch that made it, so it
# only stops answering once the callback returns and the dispatcher's frame is
# gone. Reading a kept event from a later event of the same watch would find it
# reset and alive, which proves nothing; expired.lua therefore uses two watches
# in one runtime, each with its own event object. The keeper stashes its event,
# and the prober, running for a different watch, reads the stashed one while no
# event of the keeper's is in flight.
#
# Its discrimination rests on the message it asserts: the prober distinguishes
# an event that answered, an event that raised something else, and the raise the
# cleared object gives.
#
# Usage: sudo bash tests/fsnotify/expired.sh

SCRIPT="tests/fsnotify/expired"
SCRATCH="/tmp/lunatik-fsnotify"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/kept"
: > "$SCRATCH/probe"

ktap_header
ktap_plan 3

mark_dmesg
run_script "$SCRIPT"

cat "$SCRATCH/kept" > /dev/null
cat "$SCRATCH/probe" > /dev/null
output=$(dmesg_since)

lunatik stop "$SCRIPT" 2>/dev/null

echo "$output" | grep -qF "fsnotify expired test note" || \
	fail "the keeper did not run, so nothing was kept"
ktap_pass "the keeper's callback ran and kept its event"

echo "$output" | grep -qF "fsnotify expired test pass" || \
	fail "the kept event did not raise: $(echo "$output" | grep -F 'fsnotify expired test')"
ktap_pass "reading a kept event outside its callback raises"

errs=$(echo "$output" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

