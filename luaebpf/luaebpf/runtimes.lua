--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Where `bpf.xdp` and `bpf.tc` leave the kernel runtimes a program file declared.
--
-- The file body runs once, on the host, and names the runtimes its functions call;
-- `luaebpf.compile` fills in the key a declaration left to the default, and the translator asks
-- whether a value a compiled function called is one of them.
-- @module luaebpf.runtimes

local insert = table.insert

local declared = {}
local known = {}

local runtimes = {}

---
-- Forgets what a previous compilation declared.
-- @function luaebpf.runtimes.reset
function runtimes.reset()
	declared, known = {}, {}
end

---
-- Records one runtime.
-- @function luaebpf.runtimes.declare
-- @tparam table runtime `{key}`, the key `nil` where the declaration took the default
-- @treturn table the same runtime
function runtimes.declare(runtime)
	known[runtime] = true
	insert(declared, runtime)
	return runtime
end

---
-- Whether a value the file body computed is a runtime of this compilation.
-- @function luaebpf.runtimes.declares
-- @param value
-- @treturn boolean
function runtimes.declares(value)
	return known[value] == true
end

---
-- The runtimes the file body declared, in order.
-- @function luaebpf.runtimes.declared
-- @treturn table
function runtimes.declared()
	return declared
end

return runtimes

