#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A callback that raises on a notification event is logged, and the next event
# on the same mark still reaches it.
#
# The raise reaches the pcall in the dispatcher, which logs it under the
# module's name and returns; the watch and its mark stay as they were. The
# second open shows the watch still delivering, so the first case cannot pass
# because the error tore the watch down. error.sh asserts the same of a
# permission event, and skips on a kernel without the permission hooks; this
# one needs none, so the raise is covered on every kernel.
#
# This test's kernel log carries a Lua error on purpose, so it asserts on that
# message instead of asserting there is none.
#
# Usage: sudo bash tests/fsnotify/raise.sh

SCRIPT="tests/fsnotify/raise"
SCRATCH="/tmp/lunatik-fsnotify"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"
: > "$SCRATCH/raised"

ktap_header
ktap_plan 3

mark_dmesg
run_script "$SCRIPT"
cat "$SCRATCH/raised" > /dev/null
raised=$(dmesg_since)

mark_dmesg
cat "$SCRATCH/raised" > /dev/null
again=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null

echo "$raised" | grep -qF "raise test: $SCRATCH/raised mask 20" || \
	fail "the callback did not run: $(echo "$raised" | grep -F 'fsnotify raise test')"
echo "$raised" | grep -qE "luafsnotify: .*raise\.lua:[0-9]+: the callback raised" || \
	fail "the raise was not logged by the module: $(echo "$raised" | grep -F 'raise.lua')"
ktap_pass "a callback that raises is logged by the module"

echo "$again" | grep -qF "raise test: $SCRATCH/raised mask 20" || \
	fail "the watch stopped delivering after the raise: $(echo "$again" | grep -F 'fsnotify raise test')"
ktap_pass "the next event on the same mark still reaches the callback"

errs=$(printf '%s\n%s\n' "$raised" "$again" | grep -E "WARNING:|UBSAN:|Internal error:|Unexpected kernel BRK" || true)
[ -n "$errs" ] && fail "kernel error while a callback raised: ${errs%%$'\n'*}"
ktap_pass "a raise in the callback trips no kernel warning"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

