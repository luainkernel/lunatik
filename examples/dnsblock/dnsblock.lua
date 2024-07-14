--
-- SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Filter DNS packets based on a blocklist

local xt = require("xtable")
local linux = require("linux")
local string = require("string")
local family = xt.family

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

local function dnsblock_mt(skb, par)
	local thoff = par.thoff
	local proto = skb:getuint8(9)

	if proto == udp then
		local dstport = linux.ntoh16(skb:getuint16(thoff + 2))
		if dstport == dns then
			local qoff = thoff + 20
			local name = get_domainname(skb, qoff)
			if check_blacklist(name) then
				print("DNS query for " .. name .. " blocked\n")
				return true
			end
		end
	end

	return false
end

xt.match{
	name = "dnsblock",
	revision = 1,
	family = family.UNSPEC,
	proto = 0,
	match = dnsblock_mt,
	checkentry = nop,
	destroy = nop,
}

