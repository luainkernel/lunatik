#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests calls to the functions a program file declares.
#   - one call, two levels, four arguments, a helper two programs share, the deepest chain
#     MAX_CALL_FRAMES takes with every level able to abort, a call asking for two results, where
#     Lua fills the second with nil, and a body with more live values than the emitter keeps in
#     registers, so the rest go to the frame
#   - a division inside a called function takes the program's default verdict, through the flag
#     each frame raises in its caller's; a row whose callee reaches nothing but its abort tail
#     loads, which it would not if that tail left R0 uninitialised, since the verifier reads R0
#     on the caller's fall-through without pairing the flag with the path; and a second pair of
#     rows declares the other default, so the answer is the verdict the file asked for
#   - the object carries one BTF FUNC per subprogram, named as the file names it
#   - five arguments, fewer arguments than the callee declares, direct or mutual recursion, and a
#     module installed as a stripped chunk reached by a call are refused with their messages and
#     lines; the same chunk handed over as the program itself is refused by its name, having no
#     call site for a line to point at. The fifth register carries the abort pointer, so four is
#     what a compiled function takes
# A lost spill is a wrong number rather than a silent pass, since the spilled row's answer is
# compared with the interpreter's like every other.
#
# Usage: sudo bash tests/luaebpf/call.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 8

output=$(luaebpf_compile call) || { comment "$output"; fail "luaebpf: call.bpf.lua did not compile"; }
output=$(luaebpf_loadall call) || { comment "$output"; fail "luaebpf: the calls did not verify"; }
ktap_pass "luaebpf: every call row verifies"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a call differs from the interpreter"; }
ktap_pass "luaebpf: every call row agrees with the interpreter"

dump=$(bpftool btf dump file "$LUAEBPF_WORK/call.bpf.o")
for name in twice quadruple four always; do
	echo "$dump" | grep -q "FUNC '$name'" || fail "luaebpf: the BTF names no subprogram '$name'"
done
echo "$dump" | grep -q "FUNC 'twice' type_id=[0-9]* linkage=static" \
	|| fail "luaebpf: a subprogram is not static in the BTF"
ktap_pass "luaebpf: the object carries one static FUNC per subprogram"

cat > "$LUAEBPF_WORK/fiveargs.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")

local function five(a, b, c, d, e)
	return a + b + c + d + e
end

return xdp.program(function(ctx)
	local v = five(1, 2, 3, 4, 5)
	return v
end)
LUA
output=$(luaebpf_refuses fiveargs "fiveargs.bpf.lua:8: a compiled function takes at most 4 arguments, not 5") \
	|| { comment "$output"; fail "luaebpf: a five-argument call is not refused"; }
ktap_pass "luaebpf: a call with five arguments is refused with its line"

cat > "$LUAEBPF_WORK/fewargs.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")

local function pair(a, b)
	return a + b
end

return xdp.program(function(ctx)
	local v = pair(1)
	return v
end)
LUA
output=$(luaebpf_refuses fewargs "fewargs.bpf.lua:8: 'pair' takes 2 arguments and is called with 1") \
	|| { comment "$output"; fail "luaebpf: a call short of an argument is not refused"; }
ktap_pass "luaebpf: a call with fewer arguments than the callee declares is refused with its line"

cat > "$LUAEBPF_WORK/recurse.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")

local function walk(n)
	if n <= 0 then
		return 0
	end
	local rest = walk(n - 1)
	return rest + n
end

return xdp.program(function(ctx)
	local v = walk(3)
	return v
end)
LUA
output=$(luaebpf_refuses recurse "recurse.bpf.lua:7: recursion through 'walk'") \
	|| { comment "$output"; fail "luaebpf: recursion is not refused"; }
ktap_pass "luaebpf: recursion is refused with its line"

# BYTECODE=1 installs a kernel script as a stripped chunk, which carries no source for a compiled
# function to be read from; the row builds one and puts it ahead of the installed roots
cat > "$LUAEBPF_WORK/helper.lua" <<'LUA'
local helper = {}

function helper.width(a, b)
	return a + b
end

function helper.prog(ctx)
	return 2
end

return helper
LUA
lunatikc -s -o "$LUAEBPF_WORK/stripped.lua" "$LUAEBPF_WORK/helper.lua" \
	|| fail "luaebpf: the case could not strip a module"
cat > "$LUAEBPF_WORK/nosource.bpf.lua" <<'LUA'
local xdp      = require("bpf.xdp")
local stripped = require("stripped")

return xdp.program(function(ctx)
	local v = stripped.width(1, 2)
	return v
end)
LUA
output=$(export LUA_PATH="$LUAEBPF_WORK/?.lua;;"; luaebpf_refuses nosource \
	"nosource.bpf.lua:5: 'width' carries no source; a stripped function cannot be compiled") \
	|| { comment "$output"; fail "luaebpf: a call into a stripped module is not refused"; }
ktap_pass "luaebpf: a call into a module stripped of its source is refused with its line"

# the same module handing over the program itself, which has no call site for a line to name
cat > "$LUAEBPF_WORK/noprogram.bpf.lua" <<'LUA'
local xdp      = require("bpf.xdp")
local stripped = require("stripped")

return xdp.program(stripped.prog, {name = "fromstripped"})
LUA
output=$(export LUA_PATH="$LUAEBPF_WORK/?.lua;;"; luaebpf_refuses noprogram \
	"'fromstripped' carries no source; a stripped function cannot be compiled") \
	|| { comment "$output"; fail "luaebpf: a program taken from a stripped module is not refused"; }
ktap_pass "luaebpf: a program whose own function carries no source is refused by its name"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

