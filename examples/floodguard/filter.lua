--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local netfilter = require("netfilter")
local netlink   = require("netlink")
local rcu       = require("rcu")
local nf        = require("linux.nf")

local family   = nf.proto
local action   = nf.action
local hooks    = nf.inet
local priority = nf.ip.pri

local THRESHOLD <const> = 100  -- packets from a source before it is blackholed
local CMD       <const> = 1    -- channel genl command
local IP_VIHL   <const> = 0    -- version/IHL byte offset
local IP_SADDR  <const> = 12   -- IPv4 source address offset

local counts  = rcu.table()    -- source address (string key) -> packet count
local channel = netlink.channel("floodguard")

local function ipv4(addr)
	return string.format("%d.%d.%d.%d",
		addr & 0xff, addr >> 8 & 0xff, addr >> 16 & 0xff, addr >> 24 & 0xff)
end

local function verdict(skb)
	local pkt = skb:data()
	if pkt:getuint8(IP_VIHL) >> 4 ~= 4 then
		return action.ACCEPT
	end
	local src = pkt:getuint32(IP_SADDR)
	local key = tostring(src)
	local n = (counts[key] or 0) + 1
	counts[key] = n
	if n == THRESHOLD then
		channel:multicast(CMD, "blackholed " .. ipv4(src))
		print("floodguard: " .. ipv4(src) .. " exceeded threshold, blackholing")
	end
	if n >= THRESHOLD then
		return action.DROP
	end
	return action.ACCEPT
end

netfilter.register{
	hook     = verdict,
	pf       = family.INET,
	hooknum  = hooks.PRE_ROUTING,
	priority = priority.RAW,
}

