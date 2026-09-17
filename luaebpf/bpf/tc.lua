--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Declares a TC program in a program file.
--
-- The file body runs on the host under `lunatikc bpf`; the function it hands here is the
-- program, compiled to eBPF and held to the subset the verifier can check. The verdicts are
-- `linux.tc`, the table the kernel scripts already use.
--
-- The program reads `skb.len`, `skb.hash`, `skb.ifindex` and `skb.ingress_ifindex`, and writes
-- `skb.priority`; `skb.data`/`skb.data_end` are the packet's bounds rather than numbers, and
-- `skb:packet()` is the packet.
--
-- `runtime(name)` is the escape hatch: a callable the program hands numbers to, which becomes a
-- call into the kernel Lua runtime of that name.
-- @module bpf.tc
-- @usage
-- local tc     = require("bpf.tc")
-- local action = require("linux.tc")
--
-- return tc.program(function(skb)
--     return action.ACT_SHOT
-- end, {egress = true})

local programs = require("luaebpf.programs")
local runtimes = require("luaebpf.runtimes")
local action   = require("linux.tc")

-- libbpf reads the program type and its attach point back from the ELF section name
-- (tools/lib/bpf/libbpf.c)
local INGRESS <const> = "tcx/ingress"
local EGRESS  <const> = "tcx/egress"

-- the kfunc lib/luatc.c publishes for a TC program, which libbpf resolves against the module's
-- own BTF
local KFUNC <const> = "bpf_luatc_run"

-- what a program may read on its context, and the one field of them the kernel lets it write.
-- tc_cls_act_is_valid_access allows a write only to mark, tc_index, priority, tc_classid,
-- cb[0..4], tstamp and queue_mapping, and a write is four bytes wide (net/core/filter.c); that
-- set is kernel policy rather than layout, so BTF cannot supply it.
local context = {
	struct = "__sk_buff",
	fields = {len = true, hash = true, ifindex = true, ingress_ifindex = true, priority = true},
	writable = {priority = true},
	packet = {base = "data", limit = "data_end"},
}

local tc = {}

---
-- Declares `fn` as a TC program.
-- @function bpf.tc.program
-- @tparam function fn the program; it takes the context and returns a verdict.
-- @tparam[opt] table opts `egress`, which attaches the program on the way out rather than in,
--   `default`, the verdict taken where the interpreter would raise (`linux.tc.ACT_OK`), and
--   `name`, what the program is called in the object, cut to the fifteen characters
--   `BPF_OBJ_NAME_LEN` leaves and made unique against the names already taken.
-- @treturn table the declared program
-- @raise `tc.program takes a function`, or `tc.program's default verdict is not a number`
function tc.program(fn, opts)
	opts = opts or {}
	if type(fn) ~= "function" then
		error("tc.program takes a function", 2)
	end
	local default = opts.default or action.ACT_OK
	if type(default) ~= "number" then
		error("tc.program's default verdict is not a number", 2)
	end
	return programs.declare{section = opts.egress and EGRESS or INGRESS, fn = fn,
		default = default, name = opts.name, context = context, kfunc = KFUNC}
end

---
-- Declares the kernel Lua runtime a compiled function calls.
--
-- Inside a compiled function the value this returns is a callable: `runtime(a, b)` hands the
-- runtime's callback each argument as a native 64-bit integer, in order, readable there as
-- `ctx:argument():getint64(0)` and its successors, and answers the verdict the callback set, or
-- `nil` where no runtime of that name could be dispatched. A program must test that answer
-- before reading it as a number.
-- @function bpf.tc.runtime
-- @tparam[opt] string name the key the runtime is registered under; by default the script the
--   program file belongs to, which is its path below `/lib/modules/lua/` without the `.bpf.lua`
--   suffix.
-- @treturn table the callable
-- @raise `tc.runtime takes a name`
-- @usage
-- local lua = tc.runtime()
function tc.runtime(name)
	if name ~= nil and type(name) ~= "string" then
		error("tc.runtime takes a name", 2)
	end
	return runtimes.declare{key = name}
end

return tc

