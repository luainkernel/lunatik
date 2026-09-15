#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the numeric for whose bounds the compiler proves.
#   - forward, zero-trip (1, 0), descending with a negative step, a step above one, a negative
#     initial value, and a nested pair, each compared with the interpreter
#   - no may_goto is emitted, since a proven bound lets the verifier walk the loop itself. The
#     verifier's own log is what says so: by the time a program is loaded the kernel has
#     rewritten a may_goto into a loop counter, and an xlated dump no longer names it
# A zero-trip and a descending loop are the two an emitter that copies OP_FORPREP without its
# iteration count gets wrong.
#
# Usage: sudo bash tests/luaebpf/forconst.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 3

output=$(luaebpf_compile forconst) || { comment "$output"; fail "luaebpf: forconst.bpf.lua did not compile"; }
log=$(luaebpf_verbose forconst)
[ -e "$LUAEBPF_PINS/nested" ] || { comment "$log"; fail "luaebpf: the loops did not verify"; }
ktap_pass "luaebpf: every constant-bound loop verifies"

output=$(luaebpf_differential 2) || { comment "$output"; fail "luaebpf: a loop differs from the interpreter"; }
ktap_pass "luaebpf: every constant-bound loop agrees with the interpreter"

echo "$log" | grep -q "may_goto" \
	&& fail "luaebpf: a loop took a may_goto header although its bounds are constants"
ktap_pass "luaebpf: a proven bound needs no may_goto"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

