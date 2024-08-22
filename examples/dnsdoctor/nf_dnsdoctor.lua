--
-- SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- DNS Doctoring using new netfilter API

local nf = require("netfilter")
local linux = require("linux")
local string = require("string")
local action = nf.action
local family = nf.family
local hooks = nf.inet_hooks
local pri = nf.ip_priority

local udp = 0x11
local dns = 0x35

local function nop() end

local function get_domain(skb, off)
	local _, nameoff, name = skb:getstring(off):find("([^\0]*)")
	return name, nameoff + 1
end

local function dnsdoctor_hook(skb)
	local proto = skb:getuint8(9)
	local ihl = (skb:getuint8(0) & 0x0F)
	local thoff = ihl * 4

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

	local packetdst = skb:getuint32(16)
	if packetdst ~= linux.hton32(dst_ip) then
		return action.ACCEPT
	end

	local srcport = linux.ntoh16(skb:getuint16(thoff))
	if srcport == dns then
		local dnsoff = thoff + 8
		local nanswers = linux.ntoh16(skb:getuint16(dnsoff + 6))

		-- check the domain name
		dnsoff = dnsoff + 12
		local domainname, nameoff = get_domain(skb, dnsoff)

		if domainname == target_dns then
			dnsoff = dnsoff + nameoff + 4 -- skip over type, label fields
			-- iterate over answers
			for i = 1, nanswers do
				local atype = linux.hton16(skb:getuint16(dnsoff + 2))
				if atype == 1 then
					skb:setuint32(dnsoff + 12, linux.hton32(target_ip))
				end
				dnsoff = dnsoff + 16
			end
		end
	end

	return action.ACCEPT
end

nf.register{
	hook = dnsdoctor_hook,
	pf = family.INET,
	hooknum = hooks.PRE_ROUTING,
	priority = pri.MANGLE + 1,
}

