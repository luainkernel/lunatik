--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Where a program constructor leaves what a program file declared.
--
-- The file body runs once, on the host, and hands its functions to `bpf.xdp` and its peers;
-- `luaebpf.compile` reads them back from here, in declaration order. Each carries the ELF
-- section its entry belongs in, which is how libbpf reads the program type back.
-- @module luaebpf.programs

local insert   = table.insert
local format   = string.format
local mathtype = math.type
local getinfo  = debug.getinfo

local declared = {}

local programs = {}

---
-- Forgets what a previous compilation declared.
-- @function luaebpf.programs.reset
function programs.reset()
	declared = {}
end

---
-- Records one program, held to what every constructor takes.
-- @function luaebpf.programs.declare
-- @tparam string constructor the constructor the program file called, `xdp.program` or its peer
-- @tparam function fn the program
-- @tparam table program `{section, default, name, context, kfunc}`
-- @treturn table the program, with `fn`
-- @raise `<constructor> takes a Lua function`, or `<file>:<line>: <constructor>'s default verdict
--   is not an integer`, the line where `fn` is defined
function programs.declare(constructor, fn, program)
	if type(fn) ~= "function" or getinfo(fn, "S").what == "C" then
		error(format("%s takes a Lua function", constructor), 2) -- each constructor tail-calls declare
	end
	if mathtype(program.default) ~= "integer" then
		local info = getinfo(fn, "S") -- a caller that returns xdp.program(...) leaves no line of its own
		error(format("%s:%d: %s's default verdict is not an integer", info.short_src, info.linedefined,
			constructor), 0)
	end
	program.fn = fn
	insert(declared, program)
	return program
end

---
-- The programs the file body declared, in order.
-- @function luaebpf.programs.declared
-- @treturn table
function programs.declared()
	return declared
end

return programs

