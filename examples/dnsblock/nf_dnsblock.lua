--
-- SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Filter DNS packets based on a blocklist using new netfilter hooks

local nf = require("netfilter")
local linux = require("linux")
local string = require("string")
local family = nf.family
local action = nf.action
local hooks = nf.inet_hooks
local priority = nf.ip_priority

local udp = 0x11
local dns = 0x35

local blacklist = {
	"github.com",
	"gitlab.com",
}

local function nop() end

local function check_blacklist(name)
	for _, v in ipairs(blacklist) do
		if string.find(name, v) ~= nil then
			return true
		end
	end
	return false
end

local function get_domainname(skb, off)
	local name = ""
	local i = 0

	repeat
		local d = skb:getbyte(off + i)
		i = i + 1
	until d == 0

	return name .. skb:getstring(off, i)
end

local function dnsblock_hook(skb)
	local proto = skb:getuint8(9)
	local ihl = (skb:getuint8(0) & 0x0F)
	local thoff = ihl * 4

	if proto == udp then
		local dstport = linux.ntoh16(skb:getuint16(thoff + 2))
		if dstport == dns then
			local qoff = thoff + 20
			local name = get_domainname(skb, qoff)
			if check_blacklist(name) then
				print("DNS query for " .. name .. " blocked\n")
				return action.DROP
			end
		end
	end

	return action.ACCEPT
end

nf.register{
	hook = dnsblock_hook,
	pf = family.INET,
	hooknum = hooks.LOCAL_OUT,
	priority = priority.FILTER,
}

