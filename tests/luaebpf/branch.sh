#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests comparisons and branches against the interpreter.
#   - == ~= < <= > >= in their register (EQ, LT, LE) and immediate (EQI, LTI, LEI, GTI, GEI,
#     EQK) forms, over pairs that put a negative against a positive on every relation, which an
#     unsigned jump gets wrong
#   - if/elseif/else, and, or, not, TEST and TESTSET
#   - Lua's truth, which the bits do not carry: 0 is true, and only false and nil are not
#   - a comparison held in a register as a boolean, and an 'or' of two, then tested
#   - '==' against nil, true, false and a string the body captured, where the compiler holds the
#     other side's type but not its value, so only the two types answer: in a register, false,
#     nil and the integer zero are one word
#   - no row of the corpus stops, and the run of every one of them writes no line into the trace
#     ring, which only a stop writes
#
# Usage: sudo bash tests/luaebpf/branch.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 3

# the lines the trace ring gained since luaebpf_mark emptied it, over the corpus's rows, whose
# programs each carry a stop, the write of the map that keeps its value, so their load enabled the
# event a line is written through
silent() {
	local lines
	grep -qx 1 "$TRACING/events/bpf_trace/bpf_trace_printk/enable" || echo "the event of bpf_trace_printk is off"
	lines=$(luaebpf_traced)
	[ -z "$lines" ] || echo "the corpus, whose rows stop nowhere, logged '$lines'"
}

output=$(luaebpf_compile branch) || { comment "$output"; fail "luaebpf: branch.bpf.lua did not compile"; }
output=$(luaebpf_loadall branch) || { comment "$output"; fail "luaebpf: the corpus did not verify"; }
ktap_pass "luaebpf: every branch row verifies"

luaebpf_mark 2> /dev/null
output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a branch differs from the interpreter"; }
ktap_pass "luaebpf: every branch row agrees with the interpreter"

luaebpf_logcase "a corpus whose rows stop nowhere logs nothing" silent

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

