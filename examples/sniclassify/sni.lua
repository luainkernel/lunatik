--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Based on https://github.com/luainkernel/lunatik/blob/master/examples/filter/sni.lua

local tc      = require("tc")
local action  = require("linux.tc").action
local set     = require("set")
local sni     = require("examples.common.sni")

local function TC_H_MAKE(maj, min)
	return (maj << 16) | min
end

local policy = set.labeled{
	["netflix.com"] = TC_H_MAKE(1, 0x30),
	["zoom.com"]    = TC_H_MAKE(1, 0x10),
}

local function log(host, priority)
	print(string.format("sniclassify: %s %s", host, priority))
end

local function sniclassify(ctx)
	local skb     = ctx:skb()
	local packet  = skb:data()
	local payload = ctx:argument():getuint32(0)
	local host    = sni(packet, payload)

	if host then
		local classid = policy:match(host)
		if classid ~= 0 then
			log(host, classid)
			skb:priority(classid)
		end
	end

	return action.OK
end

tc.attach(sniclassify)

