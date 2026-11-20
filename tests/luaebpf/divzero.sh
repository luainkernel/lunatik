#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what a compiled program does where the interpreter raises.
#   - x // 0 and x % 0, by a constant divisor and by one the program computes, return
#     XDP_ABORTED and not the program's default verdict, which these programs set to
#     XDP_REDIRECT, and keep nothing
#   - one run of each writes into the trace ring the error the interpreter raises there, its file
#     and line, "attempt to divide by zero" and "attempt to perform 'n%0'", once and alone, and
#     counts one stop at that line's place and none at another, past twenty runs of
#     mininteger // -1, which does not stop: they write and count nothing and spend none of the
#     rate limit, which only a stop counts
#   - twenty runs of one log ten lines and count twenty stops at its place, since a stop counts
#     before the rate limit decides, a run of another program of the object logs none after them
#     and counts one, and a run five seconds past the first logs one more: the kernel's default
#     rate limit, DEFAULT_RATELIMIT_BURST lines every DEFAULT_RATELIMIT_INTERVAL, counted in the
#     object loaded again, whose programs share one window, which opens with its first stop
#   - mininteger // -1 and x % -1, which Lua defines and C does not, match the interpreter
#   - with LUAEBPF_DROP=divisor the divisor test is gone and the same programs keep eBPF's own
#     answers instead of stopping, which is what proves the test is emitted
#
# Usage: sudo bash tests/luaebpf/divzero.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 5

DIVIDE="attempt to divide by zero" # luaV_idiv, lua/lvm.c
MODULO="attempt to perform 'n%0'"  # luaV_mod
BURST=10                           # DEFAULT_RATELIMIT_BURST, include/linux/ratelimit_types.h
RUNS=20
WINDOW=6                           # seconds, past DEFAULT_RATELIMIT_INTERVAL's five

# the line each division by zero logs, the first stops of the object, past $RUNS runs of a division
# that does not stop, which log and count nothing and spend none of the rate limit the stops then
# log under
divisions() {
	local lines before
	before=$(luaebpf_counts)
	lines=$(luaebpf_logged idivminus3 "" "" "$RUNS")
	[ -z "$lines" ] || echo "idivminus3, which does not stop, logged '$lines'"
	[ "$(luaebpf_counts)" = "$before" ] || echo "idivminus3, which does not stop, counted a stop"
	luaebpf_logs idivzero1 "$(luaebpf_logline divzero "function makers.idivzero" "$DIVIDE")"
	luaebpf_logs modzero1 "$(luaebpf_logline divzero "function makers.modzero" "$MODULO")"
	luaebpf_logs idivreg1 "$(luaebpf_logline divzero "function makers.idivreg" "$DIVIDE")"
	luaebpf_logs modreg1 "$(luaebpf_logline divzero "function makers.modreg" "$MODULO")"
}

# the lines $RUNS runs of a division by zero log, and the stops they count, all of them, those of
# another program of the object after them, and those of one run past the window they opened
limited() {
	local logged before idivzero modzero
	idivzero=$(luaebpf_logline divzero "function makers.idivzero" "$DIVIDE")
	modzero=$(luaebpf_logline divzero "function makers.modzero" "$MODULO")
	rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
	luaebpf_loadall divzero > /dev/null || { echo "the corpus did not verify again"; return; }
	before=$(luaebpf_counts)
	logged=$(luaebpf_logged idivzero1 "" "" "$RUNS" | grep -c .)
	[ "$logged" -eq "$BURST" ] || echo "$RUNS runs logged $logged lines, not $BURST"
	luaebpf_counted "$before" "$(luaebpf_counts)" "$idivzero" "$RUNS"
	before=$(luaebpf_counts)
	logged=$(luaebpf_logged modzero1 | grep -c .)
	[ "$logged" -eq 0 ] || echo "modzero1 logged $logged lines in the window idivzero1 spent"
	luaebpf_counted "$before" "$(luaebpf_counts)" "$modzero" 1
	sleep "$WINDOW"
	luaebpf_logs idivzero1 "$idivzero"
}

output=$(luaebpf_compile divzero) || { comment "$output"; fail "luaebpf: divzero.bpf.lua did not compile"; }
output=$(luaebpf_loadall divzero) || { comment "$output"; fail "luaebpf: the corpus did not verify"; }
ktap_pass "luaebpf: every division row verifies"

luaebpf_logcase "a division by zero logs the interpreter's error at its file and line, once" divisions

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a division differs from the interpreter"; }
ktap_pass "luaebpf: a division by zero returns XDP_ABORTED, and the rest match the interpreter"

luaebpf_logcase "$RUNS stops log $BURST lines and count $RUNS, and a stop $WINDOW seconds later logs one more" limited

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile divzero divisor) || { comment "$output"; fail "luaebpf: the dropped build failed"; }
output=$(luaebpf_loadall divzero) || { comment "$output"; fail "luaebpf: the dropped corpus did not verify"; }
raw=$(luaebpf_keeps idivzero1)
[ "$raw" = absent ] && fail "luaebpf: a division by zero still stopped the program with the test dropped"
[ "$raw" = "1" ] || fail "luaebpf: eBPF's own answer for 7 // 0 is 0, so 7 // 0 + 1 is 1, got '$raw'"
raw=$(luaebpf_keeps modzero1)
[ "$raw" = "7" ] || fail "luaebpf: eBPF's own answer for 7 % 0 is the dividend, got '$raw'"
ktap_pass "luaebpf: without the divisor test the raw eBPF answers come through"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

