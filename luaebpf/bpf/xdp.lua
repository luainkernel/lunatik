--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Declares an XDP program in a program file.
--
-- The file body runs on the host under `lunatikc bpf`; the function it hands here is the
-- program, compiled to eBPF and held to the subset the verifier can check. The verdicts are
-- `linux.xdp`, the table the kernel scripts already use.
--
-- The program reads `ctx.ingress_ifindex` and `ctx.rx_queue_index`; XDP publishes no writable
-- field, and `ctx.data`/`ctx.data_end` are the packet's bounds rather than numbers.
-- @module bpf.xdp
-- @usage
-- local xdp    = require("bpf.xdp")
-- local action = require("linux.xdp")
--
-- return xdp.program(function(ctx)
--     return action.DROP
-- end, {default = action.PASS})

local programs = require("luaebpf.programs")
local action   = require("linux.xdp")

-- what a program may read on its context, and the two members that are packet bounds rather
-- than numbers. Nothing is writable: xdp_is_valid_access refuses a write unless the program is
-- offloaded, and __is_valid_xdp_access takes only a four-byte read (net/core/filter.c).
local context = {
	struct = "xdp_md",
	fields = {ingress_ifindex = true, rx_queue_index = true},
	writable = {},
	packet = {base = "data", limit = "data_end"},
}

local xdp = {}

---
-- Declares `fn` as an XDP program.
-- @function bpf.xdp.program
-- @tparam function fn the program; it takes the context and returns a verdict.
-- @tparam[opt] table opts `default`, the verdict taken where the interpreter would raise
--   (`linux.xdp.PASS`), and `name`, what the program is called in the object, cut to the
--   fifteen characters `BPF_OBJ_NAME_LEN` leaves and made unique against the names already taken.
-- @treturn table the declared program
-- @raise `xdp.program takes a function`, or `xdp.program's default verdict is not a number`
function xdp.program(fn, opts)
	opts = opts or {}
	if type(fn) ~= "function" then
		error("xdp.program takes a function", 2)
	end
	local default = opts.default or action.PASS
	if type(default) ~= "number" then
		error("xdp.program's default verdict is not a number", 2)
	end
	return programs.declare{kind = "xdp", fn = fn, default = default, name = opts.name,
		context = context}
end

return xdp

