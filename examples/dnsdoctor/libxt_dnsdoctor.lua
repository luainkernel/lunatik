--
-- SPDX-FileCopyrightText: (c) 2025 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local luaxt = require("luaxt")
local family = luaxt.family

local function nop() end

local function dnsdoctor_init(par)
	local target_ip = "10.1.2.3"
	local target = 0
	target_ip:gsub("%d+", function(s) target = target * 256 + tonumber(s) end)

	local src_ip = "10.1.1.2"
	local src = 0
	src_ip:gsub("%d+", function(s) src = src * 256 + tonumber(s) end)

	par.userargs = string.pack(">s4I4I4", "\x07lunatik\x03com", src, target)
end

luaxt.target{
	revision = 0,
	family = family.UNSPEC,
	help = nop,
	init = dnsdoctor_init,
	print = nop,
	save = nop,
	parse = nop,
	final_check = nop
}

