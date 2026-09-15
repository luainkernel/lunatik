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
--
-- `runtime(name)` is the escape hatch: a callable the program hands numbers to, which becomes a
-- call into the kernel Lua runtime of that name.
-- @module bpf.xdp
-- @usage
-- local xdp    = require("bpf.xdp")
-- local action = require("linux.xdp")
--
-- return xdp.program(function(ctx)
--     return action.DROP
-- end, {default = action.PASS})

local programs = require("luaebpf.programs")
local runtimes = require("luaebpf.runtimes")
local action   = require("linux.xdp")

-- libbpf reads the program type back from the ELF section name (tools/lib/bpf/libbpf.c)
local SECTION <const> = "xdp"

-- the kfunc lib/luaxdp.c publishes for an XDP program, which libbpf resolves against the
-- module's own BTF
local KFUNC <const> = "bpf_luaxdp_run"

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
	return programs.declare{section = SECTION, fn = fn, default = default, name = opts.name,
		context = context, kfunc = KFUNC}
end

---
-- Declares the kernel Lua runtime a compiled function calls.
--
-- Inside a compiled function the value this returns is a callable: `runtime(a, b)` hands the
-- runtime's callback each argument as a native 64-bit integer, in order, readable there as
-- `ctx:argument():getint64(0)` and its successors, and answers the verdict the callback set, or
-- `nil` where no runtime of that name could be dispatched. A program must test that answer
-- before reading it as a number.
-- @function bpf.xdp.runtime
-- @tparam[opt] string name the key the runtime is registered under; by default the script the
--   program file belongs to, which is its path below `/lib/modules/lua/` without the `.bpf.lua`
--   suffix.
-- @treturn table the callable
-- @raise `xdp.runtime takes a name`
-- @usage
-- local lua = xdp.runtime()
function xdp.runtime(name)
	if name ~= nil and type(name) ~= "string" then
		error("xdp.runtime takes a name", 2)
	end
	return runtimes.declare{key = name}
end

return xdp

