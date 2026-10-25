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

# the calls sit on lines 8, 12 and 20, which the expected summary names
cat > "$LUAEBPF_WORK/report.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")

local first  = xdp.runtime("tests/luaebpf/first")
local second = xdp.runtime("tests/luaebpf/second")

-- two calls in one program
local function both(_)
	local a = first(1)
	if a then
		return a
	end
	local b = second(2)
	if b then
		return b
	end
	return 0
end

local function one(_)
	local c = second(3)
	if c then
		return c
	end
	return 0
end

xdp.program(both, {name = "both"})
xdp.program(one, {name = "one"})
LUA

summary="$LUAEBPF_WORK/report.bpf.lua:8: calls the runtime 'tests/luaebpf/first'
$LUAEBPF_WORK/report.bpf.lua:12: calls the runtime 'tests/luaebpf/second'
$LUAEBPF_WORK/report.bpf.lua:20: calls the runtime 'tests/luaebpf/second'"

output=$(cd "$LUAEBPF_WORK" && lunatik bpf -o "$LUAEBPF_WORK/report.bpf.o" "$LUAEBPF_WORK/report.bpf.lua" \
	2> "$LUAEBPF_WORK/stderr") || { comment "$(< "$LUAEBPF_WORK/stderr")"; fail "luaebpf: report.bpf.lua did not compile"; }
[ "$output" = "$summary" ] || { comment "$output"; fail "luaebpf: the summary is not one line per call, in order"; }
ktap_pass "luaebpf: every call into Lua is listed on stdout with its file, its line and its runtime"

output=$(luaebpf_compile pass) || { comment "$output"; fail "luaebpf: pass.bpf.lua did not compile"; }
[ -z "$output" ] || { comment "$output"; fail "luaebpf: a program file with no call into Lua printed a summary"; }
ktap_pass "luaebpf: a program file with no call into Lua prints no summary"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

