--
-- SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- DNS Doctoring using new netfilter API

local nf = require("netfilter")
local string = require("string")
local common = require("examples.dnsdoctor.common")
local action = nf.action
local family = nf.family
local hooks = nf.inet_hooks
local pri = nf.ip_priority

local udp = 0x11
local eth_len = 14

local function nop() end

local function dnsdoctor_hook(skb)
	local proto = skb:getuint8(eth_len + 9)
	local ihl = skb:getuint8(eth_len) & 0x0F
	local thoff = eth_len + ihl * 4
	local packet_dst = skb:getuint32(eth_len + 16)

	if proto ~= udp then
		return action.ACCEPT
	end

	local target_dns = string.pack("s1s1", "lunatik", "com")
	local dns_ip = "10.1.2.3"
	local target_ip = 0
	dns_ip:gsub("%d+", function(s) target_ip = target_ip * 256 + tonumber(s) end)

	local dst = "10.1.1.2"
	local dst_ip = 0
	dst:gsub("%d+", function(s) dst_ip = dst_ip * 256 + tonumber(s) end)

	return common.hook(skb, thoff, target_dns, target_ip, dst_ip, packet_dst)
end

nf.register{
	hook = dnsdoctor_hook,
	pf = family.INET,
	hooknum = hooks.PRE_ROUTING,
	priority = pri.MANGLE + 1,
}

