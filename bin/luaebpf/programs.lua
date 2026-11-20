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

-- a program that names no license carries one license_is_gpl_compatible counts, so its kfunc calls load
local LICENSE <const> = "Dual MIT/GPL"

local declared = {}

local programs = {}

---
-- Forgets what a previous compilation declared.
-- @function luaebpf.programs.reset
function programs.reset()
	declared = {}
end

---
-- The verdicts of a program type, from the lowest of its actions to the highest, the range the
-- kernel's Lua holds a kernel script's callback of that type to (`luakfunc_action`).
-- @function luaebpf.programs.actions
-- @tparam table action the type's actions by name, `linux.xdp.action` or its peer
-- @tparam string name what a verdict outside them is not, `an XDP action` or its peer
-- @treturn table `{first, last, name}`
function programs.actions(action, name)
	local first, last = math.maxinteger, math.mininteger
	for _, value in pairs(action) do
		first, last = math.min(first, value), math.max(last, value)
	end
	return {first = first, last = last, name = name}
end

-- what a default verdict must be and is not, or nil where it is one of its program type's actions
local function unmet(program)
	local default, actions = program.default, program.actions
	if math.type(default) ~= "integer" then
		return "an integer"
	end
	if default < actions.first or default > actions.last then
		return actions.name
	end
end

-- why a program's license cannot be the object's, or nil where it can: libbpf loads every program
-- of an object under the one string of its license section
local function unlicensed(program)
	local license, first = program.license, declared[1]
	if type(license) ~= "string" then
		return "is not a string"
	end
	if first ~= nil and license ~= first.license then
		return string.format("'%s' is not '%s', the license of the programs before it", license, first.license)
	end
end

local function refuse(constructor, fn, reason)
	local info = debug.getinfo(fn, "S") -- a caller that returns xdp.program(...) leaves no line of its own
	error(string.format("%s:%d: %s's %s", info.short_src, info.linedefined, constructor, reason), 0)
end

---
-- Records one program, held to what every constructor takes.
-- @function luaebpf.programs.declare
-- @tparam string constructor the constructor the program file called, `xdp.program` or its peer
-- @tparam function fn the program
-- @tparam table program `{section, default, error, name, license, context, kfunc, actions}`,
--   `actions` the verdicts of its type, `{first, last, name}`, and `license`, `Dual MIT/GPL` where
--   it is nil
-- @treturn table the program, with `fn`
-- @raise `<constructor> takes a Lua function`, or `<file>:<line>: <constructor>'s default verdict
--   is not an integer` or `is not <actions.name>`, or `<file>:<line>: <constructor>'s license is
--   not a string` or `'<license>' is not '<before>', the license of the programs before it`, the
--   line where `fn` is defined
function programs.declare(constructor, fn, program)
	if type(fn) ~= "function" or debug.getinfo(fn, "S").what == "C" then
		error(string.format("%s takes a Lua function", constructor), 2) -- each constructor tail-calls declare
	end
	local expected = unmet(program)
	if expected ~= nil then
		refuse(constructor, fn, "default verdict is not " .. expected)
	end
	if program.license == nil then
		program.license = LICENSE
	end
	local reason = unlicensed(program)
	if reason ~= nil then
		refuse(constructor, fn, "license " .. reason)
	end
	program.fn = fn
	table.insert(declared, program)
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

