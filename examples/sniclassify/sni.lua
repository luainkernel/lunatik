--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Based on https://github.com/luainkernel/lunatik/blob/master/examples/filter/sni.lua

local tc      = require("tc")
local action  = require("linux.tc")
local skbattr = require("skb.attr")
local set     = require("set")
local sni     = require("examples.common.sni")

local ETH_HLEN    <const> = 14
local IPPROTO_TCP <const> = 6
local HTTPS_PORT  <const> = 443
local IP_PROTO    <const> = 9
local IHL_MASK    <const> = 0x0f
local TCP_DPORT   <const> = 2
local TCP_DOFF    <const> = 12

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

-- offset of the TCP payload in an IPv4/TCP:443 frame, or nil for anything else
local function tcp_payload(packet)
	local version_ihl = packet:getbyte(ETH_HLEN)
	if version_ihl >> 4 ~= 4 or packet:getbyte(ETH_HLEN + IP_PROTO) ~= IPPROTO_TCP then
		return
	end
	local tcp = ETH_HLEN + (version_ihl & IHL_MASK) * 4
	if (packet:getbyte(tcp + TCP_DPORT) << 8 | packet:getbyte(tcp + TCP_DPORT + 1)) ~= HTTPS_PORT then
		return
	end
	return tcp + (packet:getbyte(tcp + TCP_DOFF) >> 4) * 4
end

local function sniclassify(ctx)
	local raw     = ctx:skb()
	local skb     = skbattr.new(raw)
	local packet  = raw:data()
	local payload = tcp_payload(packet)
	local host    = payload and sni(packet, payload)

	if host then
		local classid = policy:match(host)
		if classid ~= 0 then
			log(host, classid)
			skb.priority = classid
		end
	end

	ctx:action(action.ACT_OK)
end

tc.attach(sniclassify)

