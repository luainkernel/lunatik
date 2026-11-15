--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Names a kernel Lua runtime in a program file.
--
-- The compile-time twin of the kernel `lunatik`: `runtime` takes the script a runtime runs, as the
-- kernel's does, and names the runtime `lunatik run` starts from that script instead of creating
-- one.
-- @module lunatik
-- @usage
-- local xdp     = require("bpf.xdp")
-- local lunatik = require("lunatik")
-- local action  = require("linux.xdp").action
--
-- local limits = lunatik.runtime("limits")
--
-- return xdp.program(function(ctx)
--     local p = ctx:packet()
--     local port = p:getbyte(36) << 8 | p:getbyte(37)
--     local verdict = limits:run(port, #p)
--     if verdict then
--         return verdict
--     end
--     return action.PASS
-- end)

local lowering = require("luaebpf.emit.runtime")

local lunatik = {}

---
-- Naming a kernel Lua runtime in a program file.
--
-- `lunatik.runtime` runs in the body of a program file, under `lunatik bpf`, and names a runtime
-- by the script it runs, which `lunatik run` starts; a program's own function calls the runtime's
-- `run` method, and the call lowers to the kfunc of the program's type, `bpf_luaxdp_run` in an XDP
-- program and `bpf_luatc_run` in a TC one. The call answers the verdict the runtime's callback
-- returns, or nil, and the program tests the answer before it reads it. A kernel script the body
-- requires that itself requires `lunatik` gets this twin, which holds `runtime` alone.
-- @section name

---
-- Names the kernel Lua runtime a program calls.
--
-- Inside a program's own function the runtime's `run` method is called with numbers,
-- `limits:run(a, b)`, and the call runs the callback the runtime registered with the attach of the
-- program's type, `xdp.attach` or `tc.attach`, handing it the program's context and each argument as
-- a 64-bit integer, in order, which the callback reads as `ctx:argument():getint64(0)`, `getint64(8)`
-- and on. The call answers the verdict the callback returns, or `nil` where the kfunc returns `-1`:
-- no softirq runtime of that name with a callback attached, a callback that raises, returns `nil` or
-- a value outside `linux.xdp.action` or `linux.tc.action`, or one that returns
-- `linux.tc.action.UNSPEC`, which is `-1`. The program tests the answer before it reads it, with
-- `if v then`, `if not v then`, `v == nil` or `v ~= nil`; every other use is refused at its line, and
-- so are a call of the runtime itself, `limits(a)`, and any other method.
-- An object with such a call loads where the module publishes its BTF (`make btf_install`).
-- @function lunatik.runtime
-- @tparam string script the script the runtime runs, as `lunatik run` takes it, its path below
--   `/lib/modules/lua/` without `.lua`
-- @treturn table the runtime, whose `run` a program calls
-- @raise `<file>:<line>: lunatik.runtime takes a script`, the line that called it
function lunatik.runtime(script)
	if type(script) ~= "string" then
		error("lunatik.runtime takes a script", 2)
	end
	return setmetatable({key = script}, lowering.proxy)
end

return lunatik

