--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Declares an XDP program in a program file.
--
-- The body of a program file runs on the host under `lunatik bpf`; the function it hands to
-- `program` is compiled to eBPF and runs in the kernel on each packet the device receives. It takes
-- one argument, the context, and returns a verdict, a value of `linux.xdp.action`, as a kernel
-- script's xdp callback does. Where it computes a verdict that is no action, and where Lua would
-- raise, at a read past the packet or a division by 0, the program stops and returns its default
-- verdict; a verdict the compiler holds that is no action, and a boolean, are refused, "the verdict
-- 11 is not an XDP action" and "the verdict may be a boolean here; return an action".
--
-- The context has the methods of the kernel's XDP `ctx` object: `ctx:packet()`, the packet, read
-- with `getbyte`, `getint16` and the other reads of the kernel's `data` object, in the kernel's
-- byte order; `ctx:ingress()`, the index of the device the packet arrived on; and `ctx:queue()`,
-- the receive queue it arrived in, neither writable. Any other method is refused, "the context has
-- no method '<name>'".
-- `ctx.data` and `ctx.data_end` are the bounds of the packet, not numbers; `#p` is its length.
-- @module bpf.xdp
-- @usage
-- local xdp    = require("bpf.xdp")
-- local action = require("linux.xdp").action
--
-- return xdp.program(function(ctx)
--     local p = ctx:packet()
--     if p:getbyte(12) == 0x08 and p:getbyte(13) == 0x00 then -- IPv4
--         return action.DROP
--     end
--     return action.PASS
-- end)

local programs = require("luaebpf.programs")
local action   = require("linux.xdp").action

-- libbpf reads the program type back from the ELF section name (tools/lib/bpf/libbpf.c)
local SECTION <const> = "xdp"

-- the verdicts the kernel's xdp callback is held to, luakfunc_action's range in lib/luaxdp.c
local actions = {first = action.ABORTED, last = action.REDIRECT, name = "an XDP action"}

-- what a program reaches on its context, spelled as the kernel's XDP ctx object spells it
-- (lib/luaxdp.c): each method maps to the xdp_md field it reads. Nothing is writable:
-- xdp_is_valid_access refuses a write unless the program is offloaded, and __is_valid_xdp_access
-- takes only a four-byte read (net/core/filter.c).
local context = {
	struct = "xdp_md",
	methods = {ingress = "ingress_ifindex", queue = "rx_queue_index"},
	writable = {},
	packet = {method = "packet", base = "data", limit = "data_end"},
}

local xdp = {}

---
-- Declares `fn` as an XDP program.
-- @function bpf.xdp.program
-- @tparam function fn the program; it takes the context and returns a verdict.
-- @tparam[opt] table opts `default`, the verdict the program returns where it stops, an action
--   (`linux.xdp.action.PASS`), and `name`, what the program is called in the object,
--   cut to the fifteen characters `BPF_OBJ_NAME_LEN` leaves and made unique against the names
--   already taken.
-- @treturn table the declared program
-- @raise `xdp.program takes a Lua function`, or `<file>:<line>: xdp.program's default verdict is not
--   an integer` or `is not an XDP action`, the line where `fn` is defined
function xdp.program(fn, opts)
	opts = opts or {}
	return programs.declare("xdp.program", fn, {section = SECTION, default = opts.default or action.PASS,
		name = opts.name, context = context, actions = actions})
end

return xdp

