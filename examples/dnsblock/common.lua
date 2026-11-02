--
-- SPDX-FileCopyrightText: (c) 2024-2026 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Blacklist and DNS query match that nf_dnsblock's hook calls

local byteorder = require("byteorder")
local string = require("string")

local common = {}

local udp = 0x11
local dns = 0x35

local blacklist = {
	"example.net",
}

local function get_domain(skb, off)
	local _, _, name = skb:getstring(off):find("([^\0]*)")
	return name
end

local function decode_domain(name)
	local labels = {}
	local i = 1
	while i <= #name do
		local length = string.byte(name, i)
		table.insert(labels, string.sub(name, i + 1, i + length))
		i = i + length + 1
	end
	return table.concat(labels, ".")
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
				print("DNS query for " .. decode_domain(name) .. " blocked")
				return true
			end
		end
	end

	return false
end

return common

