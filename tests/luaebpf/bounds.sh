#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the bounds check every packet access carries.
#   - a read one byte past the last, a read at an offset above the ceiling the verifier lets a
#     packet pointer take, and a read that lands in the whole ClientHello but past the truncated
#     one: the interpreter raises on each, and the compiled program owes its default verdict
#   - every row is declared twice, once with each default, so the answer is the verdict the file
#     asked for and not a number the failure path happened to leave in R0
#   - with LUAEBPF_DROP=bounds the object is still written, and the verifier rejects it naming an
#     invalid packet access, which is what says the check is emitted rather than implied
#
# Usage: sudo bash tests/luaebpf/bounds.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 3

output=$(luaebpf_compile bounds) || { comment "$output"; fail "luaebpf: bounds.bpf.lua did not compile"; }
output=$(luaebpf_loadall bounds) || { comment "$output"; fail "luaebpf: the bounds checks did not verify"; }
ktap_pass "luaebpf: every out-of-bounds row verifies"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a bounds row differs from the interpreter"; }
ktap_pass "luaebpf: every out-of-bounds read takes the verdict its program declared"

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile bounds bounds) || { comment "$output"; fail "luaebpf: the dropped build failed"; }
[ -e "$LUAEBPF_WORK/bounds.bpf.o" ] || fail "luaebpf: the drop hook broke the compile, not the emission"
output=$(luaebpf_loadall bounds 2>&1)
echo "$output" | grep -q "invalid access to packet" \
	|| { comment "$output"; fail "luaebpf: without its bounds check the load was not refused for the packet"; }
ktap_pass "luaebpf: without the bounds check the verifier refuses the packet access"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

