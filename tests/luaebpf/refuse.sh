#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests every construct the phase 1 subset refuses. Each row is a program file of its own,
# written here so that the message and the line it must name sit beside the source that
# provokes them, and asserted three ways: the exact message, the non-zero exit, and that no
# object was left behind.
#
# The rows are the runtime table and its constructor, a runtime string operation, a closure, a
# vararg function, a metatable, an unresolvable global and an unresolvable
# field of a compile-time module, which are one opcode and read back as what the source says, a
# call through an unresolvable value, the context, '..', '#', a method call, a tail call, an upvalue
# assignment, a to-be-closed variable, a generic for, and a program declared with an
# argument beyond the context; and what the host adds, since the body runs in the CLI's Lua: a float
# its libraries return, as a value, as a field of a table and as the default verdict, a float
# literal, which lunatic refuses to parse, a C function, which has no bytecode, and a function the
# CLI's Lua compiled from a string, which lunatic never saw.
#
# Usage: sudo bash tests/luaebpf/refuse.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

ROWS=22

luaebpf_start $ROWS

refused() {
	local name="$1" message="$2" output
	output=$(luaebpf_refuses "$name" "$message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message"
	fi
}

# every row is one compiled function, so the header and the trailer are the same for all of them
row() {
	local name="$1" message="$2" body="$3" preamble="${4:-}" params="${5:-ctx}"
	{
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo "$preamble"
		echo "return xdp.program(function($params)"
		echo "$body"
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	refused "$name" "$message"
}

row table_new "table_new.bpf.lua:5: a table constructor cannot run in the kernel" \
	$'\tlocal t = {}\n\treturn t[1]'
row table_write "table_write.bpf.lua:6: a table cannot be written in a compiled function" \
	$'\tlocal t = ports\n\tt[1] = 2\n\treturn 0' 'local ports = {}'
row string_op "string_op.bpf.lua:5: '..' cannot be applied in a compiled function" \
	$'\tlocal s = name .. "x"\n\treturn #s' 'local name = "a"'
row length "length.bpf.lua:5: '#' cannot be applied in a compiled function" \
	$'\tlocal n = #ports\n\treturn n' 'local ports = {1, 2}'
row closure "closure.bpf.lua:5: a closure cannot be created in a compiled function" \
	$'\tlocal f = function() return 1 end\n\treturn f()'
row vararg "vararg.bpf.lua:4: a vararg function cannot be compiled" \
	$'\tlocal n = select("#", ...)\n\treturn n' '' '...'
row metatable "metatable.bpf.lua:5: a method call cannot be compiled" \
	$'\tlocal v = proxy:get()\n\treturn v' 'local proxy = setmetatable({}, {__index = function() end})'
row unknown_global "unknown_global.bpf.lua:5: global 'nowhere' is not a compile-time value" \
	$'\treturn nowhere'
row unknown_field "unknown_field.bpf.lua:5: 'action.TYPO' is not a compile-time value" \
	$'\treturn action.TYPO' 'local action = require("linux.xdp").action'
row context "context.bpf.lua:5: the program context cannot be read yet" \
	$'\treturn ctx'
row self_call "self_call.bpf.lua:5: a method call cannot be compiled" \
	$'\tlocal v = ports:len()\n\treturn v' 'local ports = {}'
row tailcall "tailcall.bpf.lua:5: a tail call cannot be compiled" \
	$'\treturn double(1)' 'local function double(x) return x + x end'
row setupvalue "setupvalue.bpf.lua:5: an upvalue cannot be assigned in a compiled function" \
	$'\tcount = 5\n\treturn count' 'local count = 0'
row toclose "toclose.bpf.lua:5: a to-be-closed variable cannot be compiled" \
	$'\tlocal h <close> = handle\n\treturn 0' 'local handle = setmetatable({}, {__close = function() end})'
row generic_for "generic_for.bpf.lua:5: a generic 'for' cannot be compiled" \
	$'\tfor k, v in next, ports do return v end\n\treturn 0' 'local ports = {1}'
row twoargs "twoargs.bpf.lua:4: a program takes one argument, the context" \
	$'\treturn extra' '' 'ctx, extra'
row float "float.bpf.lua:5: 'half' is a float, which a compiled function cannot hold" \
	$'\treturn half' 'local half = math.sqrt(4)'
row literal "literal.bpf.lua:3: malformed number near '.5'" $'\treturn half' 'local half = 2.5'
row floatfield "floatfield.bpf.lua:5: 'half' is a float, which a compiled function cannot hold" \
	$'\treturn sizes.half' 'local sizes = {half = math.sqrt(4)}'

cat > "$LUAEBPF_WORK/floatdefault.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")

return xdp.program(function(_)
	return 2
end, {default = math.sqrt(4)})
LUA
refused floatdefault "floatdefault.bpf.lua:3: xdp.program's default verdict is not an integer"

cat > "$LUAEBPF_WORK/cfunction.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")

return xdp.program(string.len)
LUA
refused cfunction "xdp.program takes a Lua function"

cat > "$LUAEBPF_WORK/loaded.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")

return xdp.program(load("return function(ctx) return 2 end")())
LUA
refused loaded '[string "return function(ctx) return 2 end"]:1: a compiled function is defined in the program file'

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

