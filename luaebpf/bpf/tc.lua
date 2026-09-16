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
-- `skb.priority`; `skb.data`/`skb.data_end` are the packet's bounds rather than numbers.
--
-- `skb:packet()` is the packet: a proxy carrying the method names of the `data` object a kernel
-- script sees, so one helper reads the same bytes on both sides. Every read lowers to a single
-- eBPF load of its own width, under a test of the offset against the last one a read that wide
-- can start at and a test of the address against the packet's end:
--
--  * `getbyte` and `getuint8`, a one-byte load; `getuint16`, `getuint32`, two and four bytes;
--    `getint64` and `getnumber`, eight;
--  * `getint8`, `getint16` and `getint32`, the same load followed by the shift pair that
--    sign-extends it, since `BPF_MEMSX` landed in v6.6 and the tree supports 5.15;
--  * `getstring(at, len)`, a call to `bpf_skb_load_bytes` over sixty-four bytes of the reading
--    function's frame, zeroed first;
--  * `#packet`, the distance between the packet's bounds.
--
-- There is no `getuint64`, because the kernel object has none: a Lua integer is 64-bit signed and
-- an unsigned one has no distinct representation. A read that fails either test does not raise --
-- there is nothing to raise to -- and the program takes its default verdict instead.
--
-- What the proxy refuses, each naming its line: a method neither it nor the context publishes, by
-- name; an accessor called with no offset, or with one that is not a number; a `getstring` with no
-- length, with a length the compiler cannot bound against a constant, or with one bounded above
-- the sixty-four bytes it reads into. What a read answered is a string the compiler holds the
-- frame offset of, and its only uses are `==` against a string constant, a `c<n>` map key and a
-- `return` from a function the program calls; anything else, arithmetic and `..` and `#` among
-- them, is refused where it is written, and the program's own `return` of one is refused as a
-- verdict it is not.
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
-- bpf_skb_load_bytes, the helper a getstring lowers to, is v4.1, below every kernel the tree
-- supports, so it carries no probe where the XDP twin does
local context = {
	struct = "__sk_buff",
	fields = {len = true, hash = true, ifindex = true, ingress_ifindex = true, priority = true},
	writable = {priority = true},
	packet = {base = "data", limit = "data_end"},
	loadbytes = {number = 26},
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

