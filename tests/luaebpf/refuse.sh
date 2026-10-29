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
# The rows are the runtime table and its constructor, a write through an upvalue to a global, to
# a table of the body and to a field of a map, a runtime string operation, a closure, a
# vararg function, pcall, a coroutine, a metatable, an unresolvable global and an unresolvable
# field of a compile-time module, which are one opcode and read back as what the source says, a
# call through an unresolvable value, the context and a string the body holds, alone and joined
# with another, '..', '#', a method call, a tail call, an upvalue
# assignment, a to-be-closed variable, a generic for, while, repeat, a program declared with an
# argument beyond the context, arithmetic on a boolean at each shape the emitter checks on its
# own: the two opcodes the VM follows with no metamethod, a binary opcode with both operands
# live, one whose result is written over the operand it read, and a shift whose constant is on
# the left; arithmetic on a nil, which is a local declared without a value; the two comparisons a
# join leaves undecidable, where a register carries one of several types and its bits say which
# for none of them, and for that reason a verdict that may be nil; arithmetic on such a join and a
# test of one, each refusal naming the types the join holds; and what the host adds, since
# the body runs in the CLI's Lua: a float its libraries return, as a value, as a field of a table
# and as the default verdict, a float literal, which lunatic refuses to parse, a C function, which
# has no bytecode, and a function the CLI's Lua compiled from a string, which lunatic never saw;
# and a map key or value the compiler holds that its spec does not pack, where the kernel's bpf.map
# raises in string.pack: a key in a register and as the small index a GETI carries, and a value.
#
# Usage: sudo bash tests/luaebpf/refuse.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

ROWS=46

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
row table_field "table_field.bpf.lua:5: a table cannot be written in a compiled function" \
	$'\tports.x = 2\n\treturn 0' 'local ports = {}'
row global_write "global_write.bpf.lua:5: a global cannot be assigned in a compiled function" \
	$'\tcounter = 1\n\treturn 0'
row map_field "map_field.bpf.lua:6: a map key is a number here" \
	$'\tflows.x = 1\n\treturn 0' \
	$'local map = require("bpf.map")\nlocal flows = map.hash("flows", {key = "I4", value = "I4", entries = 8})'
row string_op "string_op.bpf.lua:5: '..' cannot be applied in a compiled function" \
	$'\tlocal s = name .. "x"\n\treturn #s' 'local name = "a"'
row length "length.bpf.lua:5: '#' cannot be applied in a compiled function" \
	$'\tlocal n = #ports\n\treturn n' 'local ports = {1, 2}'
row closure "closure.bpf.lua:5: a closure cannot be created in a compiled function" \
	$'\tlocal f = function() return 1 end\n\treturn f()'
row vararg "vararg.bpf.lua:4: a vararg function cannot be compiled" \
	$'\tlocal n = select("#", ...)\n\treturn n' '' '...'
row pcall_ "pcall_.bpf.lua:5: 'pcall' is not a Lua function this program file declares" \
	$'\tlocal ok = pcall(ctx)\n\treturn 0'
row coroutine_ "coroutine_.bpf.lua:5: 'wrap' is not a Lua function this program file declares" \
	$'\tlocal c = wrap(ctx)\n\treturn 0' 'local wrap = coroutine.wrap'
row metatable "metatable.bpf.lua:5: a method call cannot be compiled" \
	$'\tlocal v = proxy:get()\n\treturn v' 'local proxy = setmetatable({}, {__index = function() end})'
row unknown_global "unknown_global.bpf.lua:5: global 'nowhere' is not a compile-time value" \
	$'\treturn nowhere'
row unknown_field "unknown_field.bpf.lua:5: 'action.TYPO' is not a compile-time value" \
	$'\treturn action.TYPO' 'local action = require("linux.xdp").action'
row unknown_call "unknown_call.bpf.lua:5: a call through a value the compiler cannot resolve" \
	$'\tlocal v = ctx(1)\n\treturn v'
row context "context.bpf.lua:5: a context has no value in the kernel here" \
	$'\treturn ctx'
row held_string "held_string.bpf.lua:5: a string has no value in the kernel here" \
	$'\treturn name' 'local name = "a"'
row join_held "join_held.bpf.lua:7: a compile-time value has no value in the kernel here" \
	$'\tlocal v = a\n\tif one < 2 then v = b end\n\treturn v' 'local one, a, b = 1, "a", "b"'
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
row while_ "while_.bpf.lua:7: 'while' and 'repeat' are not compiled yet" \
	$'\tlocal n = 0\n\twhile n < 4 do\n\t\tn = n + 1\n\tend\n\treturn n'
row repeat_ "repeat_.bpf.lua:8: 'while' and 'repeat' are not compiled yet" \
	$'\tlocal n = 0\n\trepeat\n\t\tn = n + 1\n\tuntil n > 3\n\treturn n'
row twoargs "twoargs.bpf.lua:4: a program takes one argument, the context" \
	$'\treturn extra' '' 'ctx, extra'
row unmbool "unmbool.bpf.lua:6: attempt to perform arithmetic on a boolean value" \
	$'\tlocal b = true\n\treturn -b'
row bnotbool "bnotbool.bpf.lua:6: attempt to perform arithmetic on a boolean value" \
	$'\tlocal b = true\n\treturn ~b'
row addbool "addbool.bpf.lua:6: attempt to perform arithmetic on a boolean value" \
	$'\tlocal b = true\n\treturn b + one' 'local one = 1'
row aliasbool "aliasbool.bpf.lua:5: attempt to perform arithmetic on a boolean value" \
	$'\tlocal v = true + 1\n\treturn v'
row shlbool "shlbool.bpf.lua:6: attempt to perform arithmetic on a boolean value" \
	$'\tlocal b = true\n\treturn 3 << b'
row nilarith "nilarith.bpf.lua:6: attempt to perform arithmetic on a nil value" \
	$'\tlocal v\n\treturn v + one' 'local one = 1'
row join_number "join_number.bpf.lua:7: a number or nil cannot be compared with a number here" \
	$'\tlocal v\n\tif one < 2 then v = 7 end\n\treturn v == 7' 'local one = 1'
row join_join "join_join.bpf.lua:8: a boolean or nil cannot be compared with a boolean or nil here" \
	$'\tlocal v, w\n\tif one < 2 then v = false end\n\tif one > 2 then w = false end\n\treturn v == w' \
	'local one = 1'
row join_arith "join_arith.bpf.lua:7: attempt to perform arithmetic on a number or nil value" \
	$'\tlocal v\n\tif one < 2 then v = 7 end\n\treturn v + one' 'local one = 1'
row join_truth "join_truth.bpf.lua:7: a number or nil has no truth value in a compiled function" \
	$'\tlocal v\n\tif one < 2 then v = 7 end\n\tif v then return 1 end\n\treturn 0' 'local one = 1'
row maybenil "maybenil.bpf.lua:7: the verdict may be nil here; test it first" \
	$'\tlocal v\n\tif one < 2 then v = 7 end\n\treturn v' 'local one = 1'
row float "float.bpf.lua:5: 'half' is a float, which a compiled function cannot hold" \
	$'\treturn half' 'local half = math.sqrt(4)'
row literal "literal.bpf.lua:3: malformed number near '.5'" $'\treturn half' 'local half = 2.5'
row floatfield "floatfield.bpf.lua:5: 'half' is a float, which a compiled function cannot hold" \
	$'\treturn sizes.half' 'local sizes = {half = math.sqrt(4)}'
row outsidekey "outsidekey.bpf.lua:6: the map key -1 does not fit 'I4'" \
	$'\tlocal v = flows[-1]\n\tif v then return v end\n\treturn 0' \
	$'local map = require("bpf.map")\nlocal flows = map.hash("flows", {key = "I4", value = "I4", entries = 8})'
row outsideindex "outsideindex.bpf.lua:6: the map key 200 does not fit 'i1'" \
	$'\tlocal v = small[200]\n\tif v then return v end\n\treturn 0' \
	$'local map = require("bpf.map")\nlocal small = map.hash("small", {key = "i1", value = "I4", entries = 8})'
row outsidevalue "outsidevalue.bpf.lua:6: the map value 4294967296 does not fit 'I4'" \
	$'\tflows[1] = 0x100000000\n\treturn 0' \
	$'local map = require("bpf.map")\nlocal flows = map.hash("flows", {key = "I4", value = "I4", entries = 8})'

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

