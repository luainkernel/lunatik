--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Where `bpf.xdp.runtime` and `bpf.tc.runtime` leave the kernel runtimes a program file names.
--
-- The file body runs once, on the host, and declares the runtimes its programs call; the translator
-- asks whether a value a compiled function calls is one of them.
-- @module luaebpf.runtimes

local format = string.format

local declared = {}

local runtimes = {}

---
-- Records one runtime.
-- @function luaebpf.runtimes.declare
-- @tparam string constructor the constructor the program file called, `xdp.runtime` or its peer
-- @tparam string key the name `lunatik run` registers the runtime's script under
-- @treturn table the runtime, `{key}`
-- @raise `<file>:<line>: <constructor> takes a name`, the line that called the constructor
function runtimes.declare(constructor, key)
	if type(key) ~= "string" then
		error(format("%s takes a name", constructor), 2) -- each constructor tail-calls declare
	end
	local runtime = {key = key}
	declared[runtime] = true
	return runtime
end

---
-- Whether a value the file body computed is a runtime it declared.
-- @function luaebpf.runtimes.declares
-- @param value
-- @treturn boolean
function runtimes.declares(value)
	return declared[value] == true
end

return runtimes

