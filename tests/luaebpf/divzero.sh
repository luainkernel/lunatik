#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what a compiled program does where the interpreter raises.
#   - x // 0 and x % 0, by a constant divisor and by one the program computes, return
#     XDP_ABORTED and not the program's default verdict, which these programs set to
#     XDP_REDIRECT; a quotient by zero is returned plus one, so eBPF's own quotient, 0, cannot be
#     mistaken for XDP_ABORTED
#   - mininteger // -1 and x % -1, which Lua defines and C does not, match the interpreter
#   - with LUAEBPF_DROP=divisor the divisor test is gone and the same programs return eBPF's
#     own answers instead of XDP_ABORTED, which is what proves the test is emitted
#
# Usage: sudo bash tests/luaebpf/divzero.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 3

output=$(luaebpf_compile divzero) || { comment "$output"; fail "luaebpf: divzero.bpf.lua did not compile"; }
output=$(luaebpf_loadall divzero) || { comment "$output"; fail "luaebpf: the corpus did not verify"; }
ktap_pass "luaebpf: every division row verifies"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a division differs from the interpreter"; }
ktap_pass "luaebpf: a division by zero returns XDP_ABORTED, and the rest match the interpreter"

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile divzero divisor) || { comment "$output"; fail "luaebpf: the dropped build failed"; }
output=$(luaebpf_loadall divzero) || { comment "$output"; fail "luaebpf: the dropped corpus did not verify"; }
raw=$(luaebpf_verdict idivzero1)
[ "$raw" = "0" ] && fail "luaebpf: a division by zero still returned XDP_ABORTED with the test dropped"
[ "$raw" = "1" ] || fail "luaebpf: eBPF's own answer for 7 // 0 is 0, so 7 // 0 + 1 is 1, got '$raw'"
raw=$(luaebpf_verdict modzero1)
[ "$raw" = "7" ] || fail "luaebpf: eBPF's own answer for 7 % 0 is the dividend, got '$raw'"
ktap_pass "luaebpf: without the divisor test the raw eBPF answers come through"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

