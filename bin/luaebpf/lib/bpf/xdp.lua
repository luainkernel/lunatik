--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Declares an XDP program in a program file.
--
-- The file body runs on the host under `lunatik bpf`; the function it hands here is the
-- program, compiled to eBPF and held to the subset the verifier can check. The verdicts are
-- `linux.xdp.action`, the table the kernel scripts already use.
--
-- The program's argument is spelled as the kernel's XDP `ctx` object: `ctx:ingress()` is the
-- index of the device the packet arrived on and `ctx:queue()` the receive queue it arrived in,
-- neither writable; `ctx.data`/`ctx.data_end` are the packet's bounds rather than numbers.
-- @module bpf.xdp
-- @usage
-- local xdp    = require("bpf.xdp")
-- local action = require("linux.xdp").action
--
-- return xdp.program(function(ctx)
--     return action.DROP
-- end, {default = action.PASS})

local programs = require("luaebpf.programs")
local action   = require("linux.xdp").action

-- libbpf reads the program type back from the ELF section name (tools/lib/bpf/libbpf.c)
local SECTION <const> = "xdp"

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
-- @tparam[opt] table opts `default`, the verdict taken where the interpreter would raise
--   (`linux.xdp.action.PASS`), and `name`, what the program is called in the object, cut to the
--   fifteen characters `BPF_OBJ_NAME_LEN` leaves and made unique against the names already taken.
-- @treturn table the declared program
-- @raise `xdp.program takes a Lua function`, or `<file>:<line>: xdp.program's default verdict is not
--   an integer`, the line where `fn` is defined
function xdp.program(fn, opts)
	opts = opts or {}
	return programs.declare("xdp.program", fn, {section = SECTION, default = opts.default or action.PASS,
		name = opts.name, context = context})
end

return xdp

