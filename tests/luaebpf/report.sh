#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the summary `lunatik bpf` prints: a call into the kernel Lua runtime runs the interpreter on
# the packet path, and nothing in the object says how many a program file makes, so the compiler
# lists them. The case only compiles.
#   - a program file with calls on three lines, into two runtimes, two of them in one program and
#     one in another, prints one line per call on stdout with its file, its line and the runtime's
#     name, in the order the compiler met them
#   - a program file with no call prints nothing
#
# Usage: sudo bash tests/luaebpf/report.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 2

# the calls sit on lines 15, 19 and 27, which the expected summary names
cp "$LUAEBPF_SRC/report.bpf.lua" "$LUAEBPF_WORK/"

summary="$LUAEBPF_WORK/report.bpf.lua:15: calls the runtime 'tests/luaebpf/first'
$LUAEBPF_WORK/report.bpf.lua:19: calls the runtime 'tests/luaebpf/second'
$LUAEBPF_WORK/report.bpf.lua:27: calls the runtime 'tests/luaebpf/second'"

output=$(luaebpf_written report 2> "$LUAEBPF_WORK/stderr") \
	|| { comment "$(< "$LUAEBPF_WORK/stderr")"; fail "luaebpf: report.bpf.lua did not compile"; }
[ "$output" = "$summary" ] || { comment "$output"; fail "luaebpf: the summary is not one line per call, in order"; }
ktap_pass "luaebpf: every call into Lua is listed on stdout with its file, its line and its runtime"

output=$(luaebpf_compile pass) || { comment "$output"; fail "luaebpf: pass.bpf.lua did not compile"; }
[ -z "$output" ] || { comment "$output"; fail "luaebpf: a program file with no call into Lua printed a summary"; }
ktap_pass "luaebpf: a program file with no call into Lua prints no summary"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

