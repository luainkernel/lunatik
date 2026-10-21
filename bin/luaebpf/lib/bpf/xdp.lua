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

local mathtype = math.type
local format   = string.format
local getinfo  = debug.getinfo

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
	if type(fn) ~= "function" or getinfo(fn, "S").what == "C" then
		error("xdp.program takes a Lua function", 2)
	end
	local default = opts.default or action.PASS
	if mathtype(default) ~= "integer" then
		local info = getinfo(fn, "S") -- a caller that returns xdp.program(...) leaves no line of its own
		error(format("%s:%d: xdp.program's default verdict is not an integer", info.short_src, info.linedefined), 0)
	end
	return programs.declare{kind = "xdp", fn = fn, default = default, name = opts.name}
end

return xdp

