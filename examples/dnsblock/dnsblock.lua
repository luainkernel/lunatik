--
-- SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Filter DNS packets based on a blocklist

local xt = require("xtable")
local linux = require("linux")
local string = require("string")
local action = xt.action
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
	while true do
		local d = skb:getbyte(off + i)
		if d == 0 then
			break
		end

		i = i + 1
		local len = d

		repeat
			name = name .. string.char(skb:getbyte(off + i))
			i = i + 1
			len = len - 1
		until len > 0

		name = name .. "."
	end
	return name
end

local function dnsblock_mt(skb)
	-- ip header
	local ipb = skb:getuint8(0)
	local ihlen = ((ipb << 4 ) & 0xFF) >> 4
	local iphdrlen = ihlen * 4
	local proto = skb:getuint8(9)

	if proto == udp then
		local dstport = linux.ntoh16(skb:getuint16(iphdrlen + 2))
		if dstport == dns then
			local qoff = iphdrlen + 20
			local name = get_domainname(skb, qoff)
			if check_blacklist(name) then
				print("DNS query for " .. name .. " blocked\n")
				return action.ACCEPT
			end
		end
	end

	return action.DROP
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

