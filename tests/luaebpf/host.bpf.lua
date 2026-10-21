--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the host case (see host.sh).

local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action
local proto  = require("luaebpf.proto")
local chunk  = require("tests.luaebpf.kernelchunk")

assert(math.type(10 / 4) == "integer" and 10 / 4 == 2, "the body does not compute as the kernel does")
assert(("10" // 3) == 3, "a metamethod event is not renumbered for the CLI's Lua")
assert(chunk.width == 2, "a module installed as a kernel chunk does not compute as the kernel does")
assert(action.PASS == 2, "linux.xdp.action does not carry the kernel's verdicts")
local found = debug.getinfo(require("class"), "S").source
assert(found == "@/lib/modules/lua/class.lua", "class is read from " .. found .. ", not the kernel scripts")
found = debug.getinfo(require("struct"), "S").source
assert(found == "@/lib/modules/lua/struct.lua", "struct is read from " .. found .. ", not the kernel scripts")

local function subject(a, b)
	return a + b
end

local function divide(a, b)
	return a / b
end

local function outer(_) return function(_) return 1 end end

local pass, drop = function(_) return 2 end, function(_) return 1 end

local read = proto.read(subject)
assert(read.numparams == 2, "numparams is " .. read.numparams)
assert(read.maxstacksize >= 2, "maxstacksize is " .. read.maxstacksize)
assert(read.isvararg == false, "subject is not a vararg function")
assert(read.code[1].op == proto.opcodes.ADD, "the first opcode is not ADD")
assert(read.lines[1] == 22, "the first instruction comes from line " .. read.lines[1])
assert(read.source:match("host%.bpf%.lua$"), "the source is " .. tostring(read.source))
assert(proto.read(divide).code[1].op == proto.opcodes.IDIV, "'/' is not the kernel's integer division")
assert(#proto.read(outer).protos == 1, "the function holding another on its line is not read as itself")
assert(#proto.read(outer(0)).protos == 0, "the function another holds on its line is not read as itself")
assert(proto.read(pass).code[1].sbx == 2 and proto.read(drop).code[1].sbx == 1,
	"two functions on one line are not read as themselves")
local ok, err = pcall(proto.read, xdp.program)
assert(not ok and err:match("a compiled function is defined in the program file"),
	"xdp.program, the compiler's own Lua, is read as a compiled function: " .. tostring(err))
assert(require("luaebpf.probe") == "host",
	"a luaebpf.* module the compiler itself does not load is not reached from the body")

return xdp.program(function(_)
	return action.PASS
end, {name = "host"})

