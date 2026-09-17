#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests integer arithmetic against the interpreter.
#   - every arithmetic and bitwise operator in its register, constant (K) and immediate (I)
#     forms, plus unary minus and bitwise not
#   - a corpus of operand pairs with negatives, zero, -1, mininteger, maxinteger, and shift
#     counts of 0, 1, 63, 64, 65 and -1, where eBPF masks the count and Lua yields zero
#   - SHLI, whose constant is the left operand, and SHRI, whose count Lua negates
# One program per row lands in one object; each verdict is compared with the value the program
# file's own body computed on the host, truncated to the 32 bits bpf_prog_run returns.
#
# Usage: sudo bash tests/luaebpf/arith.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 2

output=$(luaebpf_compile arith) || { comment "$output"; fail "luaebpf: arith.bpf.lua did not compile"; }
output=$(luaebpf_loadall arith) || { comment "$output"; fail "luaebpf: the corpus did not verify"; }
ktap_pass "luaebpf: every arithmetic row verifies"

output=$(luaebpf_differential 2) \
	|| { comment "$output"; fail "luaebpf: the compiled arithmetic differs from the interpreter"; }
ktap_pass "luaebpf: every arithmetic row agrees with the interpreter"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

