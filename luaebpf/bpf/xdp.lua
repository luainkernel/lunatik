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
-- `ctx:packet()` is the packet: a proxy carrying the method names of the `data` object a kernel
-- script sees, so one helper reads the same bytes on both sides. Every read lowers to a single
-- eBPF load of its own width, under a test of the offset against the last one a read that wide
-- can start at and a test of the address against the packet's end:
--
--  * `getbyte` and `getuint8`, a one-byte load; `getuint16`, `getuint32`, two and four bytes;
--    `getint64` and `getnumber`, eight;
--  * `getint8`, `getint16` and `getint32`, the same load followed by the shift pair that
--    sign-extends it, since `BPF_MEMSX` landed in v6.6 and the tree supports 5.15;
--  * `getstring(at, len)`, a call to `bpf_xdp_load_bytes` over sixty-four bytes of the reading
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
-- the sixty-four bytes it reads into; and, on a kernel below v5.18, the read itself, by the name
-- of the helper it needs and of the kernel that publishes none. What a read answered is a string
-- the compiler holds the frame offset of, and its only uses are `==` against a string constant,
-- a `c<n>` map key and a `return` from a function the program calls; anything else, arithmetic
-- and `..` and `#` among them, is refused where it is written, and the program's own `return`
-- of one is refused as a verdict it is not.
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
-- bpf_xdp_load_bytes, the helper a getstring lowers to, landed in v5.18 and the tree supports
-- 5.15, so the compiler asks the running kernel's own BTF for it rather than assuming it
local context = {
	struct = "xdp_md",
	fields = {ingress_ifindex = true, rx_queue_index = true},
	writable = {},
	packet = {base = "data", limit = "data_end"},
	loadbytes = {number = 189, probe = "bpf_xdp_load_bytes"},
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

