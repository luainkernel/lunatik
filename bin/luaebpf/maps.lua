--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Where `bpf.map` leaves what a program file declared.
--
-- The file body runs once, on the host, and declares its maps before the functions that use
-- them; `luaebpf.compile` reads them back from here, in declaration order, and the translator
-- asks whether a table a compiled function reached is one of them.
-- @module luaebpf.maps

local insert = table.insert

local declared = {}
local named = {}

local maps = {}

---
-- Forgets what a previous compilation declared.
-- @function luaebpf.maps.reset
function maps.reset()
	declared, named = {}, {}
end

---
-- Records one map.
-- @function luaebpf.maps.declare
-- @tparam table map `{name, type, entries, key, value}`
-- @treturn table|nil the same map, or `nil` when that name is already taken
function maps.declare(map)
	if named[map.name] ~= nil then
		return nil
	end
	named[map.name] = map
	insert(declared, map)
	return map
end

---
-- Whether a value the file body computed is a map of this compilation.
-- @function luaebpf.maps.declares
-- @param value
-- @treturn boolean
function maps.declares(value)
	return type(value) == "table" and named[value.name] == value
end

---
-- The maps the file body declared, in order.
-- @function luaebpf.maps.declared
-- @treturn table
function maps.declared()
	return declared
end

return maps

