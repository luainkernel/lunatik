#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the compiler's summary: a call into the kernel Lua runtime is an interpreter on the
# packet path, and nothing in the program file says how many there are, so `lunatikc bpf` lists
# them. The case only compiles, so it needs no kfunc and no runtime.
#   - a program file with a call on two known lines, each naming a runtime of its own, prints one
#     line per call with its own line number and its own key, in the order the compiler met them
#   - pass.bpf.lua, which calls no runtime, prints nothing
#
# Usage: sudo bash tests/luaebpf/report.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

SUMMARY="calls the runtime"

luaebpf_start 2

# the two calls sit on lines 7 and 11, which the assertions below name
cat > "$LUAEBPF_WORK/report.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")

local first  = xdp.runtime("tests/luaebpf/first")
local second = xdp.runtime("tests/luaebpf/second")

return xdp.program(function(ctx)
	local a = first(1)
	if a then
		return a
	end
	local b = second(2)
	if b then
		return b
	end
	return 0
end, {name = "report"})
LUA

output=$(cd "$LUAEBPF_WORK" && lunatikc bpf -o "$LUAEBPF_WORK/report.bpf.o" \
	"$LUAEBPF_WORK/report.bpf.lua" 2>&1) \
	|| { comment "$output"; fail "luaebpf: report.bpf.lua did not compile"; }

listed=$(echo "$output" | grep -c "$SUMMARY")
[ "$listed" -eq 2 ] || { comment "$output"; fail "luaebpf: the compiler listed $listed calls, not 2"; }
echo "$output" | grep -qF "report.bpf.lua:7: $SUMMARY 'tests/luaebpf/first'" \
	|| { comment "$output"; fail "luaebpf: the first call is not listed with its line and key"; }
echo "$output" | grep -qF "report.bpf.lua:11: $SUMMARY 'tests/luaebpf/second'" \
	|| { comment "$output"; fail "luaebpf: the second call is not listed with its line and key"; }
ktap_pass "luaebpf: every call into Lua is listed with its own line and its own runtime key"

output=$(luaebpf_compile pass) || { comment "$output"; fail "luaebpf: pass.bpf.lua did not compile"; }
echo "$output" | grep -q "$SUMMARY" \
	&& { comment "$output"; fail "luaebpf: a program file that calls no runtime was listed"; }
ktap_pass "luaebpf: a program file with no call into Lua prints no summary"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

