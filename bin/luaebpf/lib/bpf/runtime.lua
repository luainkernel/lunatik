--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Names a kernel Lua runtime in a program file.
--
-- The body of a program file runs on the host under `lunatik bpf` and names each runtime its
-- programs call by the script it runs; a program's own function calls the value `new` returns, and
-- the call lowers to the kfunc of the program's type, `bpf_luaxdp_run` in an XDP program and
-- `bpf_luatc_run` in a TC one. The call answers the verdict the runtime's callback returns, or nil,
-- and the program tests the answer before it reads it.
-- @module bpf.runtime
-- @usage
-- local xdp     = require("bpf.xdp")
-- local runtime = require("bpf.runtime")
-- local action  = require("linux.xdp").action
--
-- local lua = runtime.new("ports")
--
-- return xdp.program(function(ctx)
--     local p = ctx:packet()
--     local port = p:getbyte(36) << 8 | p:getbyte(37)
--     local verdict = lua(port, #p)
--     if verdict then
--         return verdict
--     end
--     return action.PASS
-- end)

local lowering = require("luaebpf.emit.runtime")

local runtime = {}

---
-- Names the kernel Lua runtime a program calls.
--
-- Inside a program's own function the value this returns is called with numbers, `lua(a, b)`, and
-- the call runs the callback the runtime registered with the attach of the program's type,
-- `xdp.attach` or `tc.attach`, handing it the program's context and each argument as a 64-bit
-- integer, in order, which the callback reads as `ctx:argument():getint64(0)`, `getint64(8)` and
-- on. The call answers the verdict the callback returns, or `nil` where the kfunc returns `-1`: no
-- softirq runtime of that name with a callback attached, a callback that raises, returns `nil` or a
-- value outside `linux.xdp.action` or `linux.tc.action`, or one that returns
-- `linux.tc.action.UNSPEC`, which is `-1`. The program tests the answer before it reads it, with
-- `if v then`, `if not v then`, `v == nil` or `v ~= nil`; every other use is refused at its line.
-- An object with such a call loads where the module publishes its BTF (`make btf_install`).
-- @function bpf.runtime.new
-- @tparam string name the script the runtime runs, as `lunatik run` takes it, its path below
--   `/lib/modules/lua/` without `.lua`
-- @treturn table the runtime, called inside a program
-- @raise `<file>:<line>: runtime.new takes a name`, the line that called it
function runtime.new(name)
	if type(name) ~= "string" then
		error("runtime.new takes a name", 2)
	end
	return setmetatable({key = name}, lowering.proxy)
end

return runtime

