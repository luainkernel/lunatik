--
-- SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local xdp    = require("xdp")
local action = require("linux.xdp")
local sni    = require("examples.common.sni")

local function set(t)
	local s = {}
	for _, key in ipairs(t) do s[key] = true end
	return s
end

local blacklist = set{
	"ebpf.io",
}

local function log(host, verdict)
	print(string.format("filter_sni: %s %s", host, verdict))
end

local function offset(argument)
	return argument:getbyte(0) << 8 | argument:getbyte(1)
end

local function filter_sni(ctx)
	local host = sni(ctx:packet(), offset(ctx:argument()))
	if host then
		local verdict = blacklist[host] and "DROP" or "PASS"
		log(host, verdict)
		ctx:action(action[verdict])
		return
	end
	ctx:action(action.PASS)
end

xdp.attach(filter_sni)

