--
-- SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Common code for new netfilter framework and legacy iptables dnsblock example

local linux = require("linux")
local byteorder = require("byteorder")
local string = require("string")

local common = {}

local udp = 0x11
local dns = 0x35

local blacklist = {
	"github.com",
	"gitlab.com",
}

local function get_domain(skb, off)
	local _, _, name = skb:getstring(off):find("([^\0]*)")
	return name
end

local function check_blacklist(name)
	for _, v in ipairs(blacklist) do
		if string.find(name, v) ~= nil then
			return true
		end
	end
	return false
end

function common.hook(skb, thoff, proto)
	if proto == udp then
		local dstport = byteorder.ntoh16(skb:getuint16(thoff + 2))
		if dstport == dns then
			local qoff = thoff + 20
			local name = get_domain(skb, qoff)
			if check_blacklist(name) then
				print("DNS query for " .. name .. " blocked\n")
				return true
			end
		end
	end

	return false
end

return common

