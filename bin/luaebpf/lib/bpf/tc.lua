--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Declares a TC program in a program file.
--
-- The body of a program file runs on the host under `lunatik bpf`; the function it hands to
-- `program` is compiled to eBPF and runs in the kernel on each packet the device receives, or
-- sends. It takes one argument, the context, and returns a verdict, a value of `linux.tc.action`,
-- as a kernel script's tc callback does: `OK`, `SHOT` and `REDIRECT` act, and the rest decides
-- nothing. Where it computes a verdict that is no action, and where Lua would raise, at a read past
-- the packet or a division by 0, the program stops and returns `TC_ACT_SHOT`, which drops the
-- packet, since TC has no verdict for a program error; where it returns no value, it returns its
-- default verdict. A verdict the compiler holds that is no action, and a boolean, are refused, "the
-- verdict 9 is not a TC action" and "the verdict may be a boolean here; return an action".
--
-- The program's argument is spelled as the kernel's `skb` object: `#skb` is the packet's length,
-- `skb:ifindex()` its device's index, `skb:hash()` its flow hash and `skb:priority()` its
-- priority, which `skb:priority(v)` sets to a value from 0 up to `U32_MAX`, returning it. A value
-- outside them is refused where the compiler holds it, and stops the program where the program
-- computes it. Any other method is refused, `skb:mark()` among them. `skb.data`/`skb.data_end` are
-- the packet's bounds rather than numbers, and `skb:data()` is the whole packet from `skb->data`,
-- `#skb` bytes long, read as `ctx:packet()` is in `bpf.xdp` whether the skb is linear or not; a
-- layer is refused.
--
-- A call into a kernel Lua runtime `lunatik.runtime` names, `r:run(a, b)`, lowers to
-- `bpf_luatc_run`: it answers the verdict the callback `tc.attach` registered returns, or nil, and
-- the program tests the answer before it reads it.
-- @module bpf.tc
-- @usage
-- local tc     = require("bpf.tc")
-- local action = require("linux.tc").action
--
-- return tc.program(function(skb)
--     if #skb > 1500 then
--         skb:priority(1)
--     end
--     return action.OK
-- end, {egress = true})

local programs = require("luaebpf.programs")
local action   = require("linux.tc").action
local func     = require("linux.bpf").func
local limits   = require("linux.limits")

-- libbpf reads the program type and its attach point back from the ELF section name
-- (tools/lib/bpf/libbpf.c)
local INGRESS <const> = "tcx/ingress"
local EGRESS  <const> = "tcx/egress"

-- what lib/luatc.c registers for a TC program, which libbpf resolves in the module's BTF
local KFUNC <const> = "bpf_luatc_run"

-- the verdicts the kernel's tc callback is held to, luakfunc_action's range in lib/luatc.c
local actions = programs.actions(action, "a TC action")

-- what a program reaches on its context, spelled as the kernel's skb object spells it
-- (lib/luaskb.c): '#' reads len and each method the field of its name, and a method the kernel
-- lets a program write takes a value. tc_cls_act_is_valid_access allows a write only to mark,
-- tc_index, priority, tc_classid, cb[0..4], tstamp and queue_mapping, and a write is four bytes
-- wide (net/core/filter.c); that set is kernel policy rather than layout, so BTF cannot supply it.
-- skb:data(layer) starts where the header its layer names does, which no compiled read reaches
-- yet, so the packet proxy is the view from skb->data and refuses a layer. In a tc callback
-- skb:data() reads an skb that is not linear whole, from a copy skb_copy_bits makes of it, and
-- bpf_skb_load_bytes is skb_header_pointer over the context up to an offset of INT_MAX
-- (net/core/filter.c), which reads the same bytes, so the packet proxy reads with it.
local context = {
	struct = "__sk_buff",
	length = "len",
	methods = {ifindex = "ifindex", hash = "hash", priority = "priority"},
	writable = {priority = true},
	packet = {method = "data", layered = true, loadbytes = func.skb_load_bytes, copymax = limits.int.MAX,
		base = "data", limit = "data_end"},
}

local tc = {}

---
-- Declares `fn` as a TC program.
-- @function bpf.tc.program
-- @tparam function fn the program; it takes the context and returns a verdict.
-- @tparam[opt] table opts `egress`, which attaches the program on the way out rather than in,
--   `default`, the verdict the program returns where its function returns no value, an action
--   (`linux.tc.action.OK`), and `name`, what the program is called in the object, cut to the
--   fifteen characters `BPF_OBJ_NAME_LEN` leaves and made unique against the names already taken.
-- @treturn table the declared program
-- @raise `tc.program takes a Lua function`, or `<file>:<line>: tc.program's default verdict is not
--   an integer` or `is not a TC action`, the line where `fn` is defined
function tc.program(fn, opts)
	opts = opts or {}
	return programs.declare("tc.program", fn, {section = opts.egress and EGRESS or INGRESS,
		default = opts.default or action.OK, error = action.SHOT, name = opts.name, context = context,
		kfunc = KFUNC, actions = actions})
end

return tc

