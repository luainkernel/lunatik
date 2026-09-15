#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that a verifier log names the Lua source, which is what .BTF.ext's line_info buys.
#   - the verifier's log quotes <file>.bpf.lua:<line> for an accepted program
#   - with LUAEBPF_DROP=lineinfo the same log carries no Lua line, so the grep discriminates
#   - with LUAEBPF_DROP=verdict the program never writes R0, the verifier rejects it, and the
#     log still names the Lua line the rejected instruction came from
#
# Usage: sudo bash tests/luaebpf/lineinfo.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 3

output=$(luaebpf_compile pass) || { comment "$output"; fail "luaebpf: pass.bpf.lua did not compile"; }
log=$(luaebpf_verbose pass)
echo "$log" | grep -qE "pass\.bpf\.lua:[0-9]+" || { comment "$log"; fail "luaebpf: the log names no Lua line"; }
ktap_pass "luaebpf: the verifier log quotes the Lua file and line"

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile pass lineinfo) || { comment "$output"; fail "luaebpf: the dropped build failed"; }
log=$(luaebpf_verbose pass)
echo "$log" | grep -qE "pass\.bpf\.lua:[0-9]+" && fail "luaebpf: the log names a Lua line with line_info dropped"
ktap_pass "luaebpf: without line_info the log names no Lua line"

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile pass verdict) || { comment "$output"; fail "luaebpf: the dropped build failed"; }
log=$(luaebpf_verbose pass)
[ -e "$LUAEBPF_PINS/pass" ] && fail "luaebpf: a program that never writes R0 loaded"
echo "$log" | grep -qE "pass\.bpf\.lua:[0-9]+" || { comment "$log"; fail "luaebpf: the rejection names no Lua line"; }
ktap_pass "luaebpf: a rejected program's log still names the Lua line"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

