--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Declares a TC program in a program file.
--
-- The file body runs on the host under `lunatik bpf`; the function it hands here is the
-- program, compiled to eBPF and held to the subset the verifier can check. The verdicts are
-- `linux.tc.action`, the table the kernel scripts already use.
--
-- The program's argument is spelled as the kernel's `skb` object: `#skb` is the packet's length,
-- `skb:ifindex()` its device's index, `skb:hash()` its flow hash and `skb:priority()` its
-- priority, which `skb:priority(v)` sets to a value from 0 up to `U32_MAX`, returning it. A value
-- outside them is refused where the compiler holds it, and takes the default verdict where the
-- program computes it. `skb.data`/`skb.data_end` are the packet's bounds rather than numbers, and
-- `skb:data()` is the packet from `skb->data`; a layer is refused, and an skb that is not linear,
-- where the kernel's `skb:data()` raises in a tc callback, takes the default verdict.
-- @module bpf.tc
-- @usage
-- local tc     = require("bpf.tc")
-- local action = require("linux.tc").action
--
-- return tc.program(function(skb)
--     return action.SHOT
-- end, {egress = true})

local programs = require("luaebpf.programs")
local action   = require("linux.tc").action

-- libbpf reads the program type and its attach point back from the ELF section name
-- (tools/lib/bpf/libbpf.c)
local INGRESS <const> = "tcx/ingress"
local EGRESS  <const> = "tcx/egress"

-- what a program reaches on its context, spelled as the kernel's skb object spells it
-- (lib/luaskb.c): '#' reads len and each method the field of its name, and a method the kernel
-- lets a program write takes a value. tc_cls_act_is_valid_access allows a write only to mark,
-- tc_index, priority, tc_classid, cb[0..4], tstamp and queue_mapping, and a write is four bytes
-- wide (net/core/filter.c); that set is kernel policy rather than layout, so BTF cannot supply it.
-- skb:data(layer) starts where the header its layer names does, which no compiled read reaches
-- yet, so the packet proxy is the view from skb->data and refuses a layer. In a tc callback
-- skb:data() raises on an skb that is not linear, so the packet proxy opens only a linear one.
local context = {
	struct = "__sk_buff",
	length = "len",
	methods = {ifindex = "ifindex", hash = "hash", priority = "priority"},
	writable = {priority = true},
	packet = {method = "data", layered = true, linear = true, base = "data", limit = "data_end"},
}

local tc = {}

---
-- Declares `fn` as a TC program.
-- @function bpf.tc.program
-- @tparam function fn the program; it takes the context and returns a verdict.
-- @tparam[opt] table opts `egress`, which attaches the program on the way out rather than in,
--   `default`, the verdict taken where the interpreter would raise (`linux.tc.action.OK`), and
--   `name`, what the program is called in the object, cut to the fifteen characters
--   `BPF_OBJ_NAME_LEN` leaves and made unique against the names already taken.
-- @treturn table the declared program
-- @raise `tc.program takes a Lua function`, or `<file>:<line>: tc.program's default verdict is not
--   an integer`, the line where `fn` is defined
function tc.program(fn, opts)
	opts = opts or {}
	return programs.declare("tc.program", fn, {section = opts.egress and EGRESS or INGRESS,
		default = opts.default or action.OK, name = opts.name, context = context})
end

return tc

