--
-- SPDX-FileCopyrightText: (c) 2024-2026 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- DNS Doctoring using the netfilter API

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local byteorder = require("byteorder")
local string    = require("string")
local action    = nf.action
local family    = nf.proto
local hooks     = nf.inet
local pri       = nf.ip.pri

local udp = 0x11
local dns = 0x35

local function get_domain(skb, off)
	local _, nameoff, name = skb:getstring(off):find("([^\0]*)")
	return name, nameoff + 1
end

local function doctor(skb, thoff, target_dns, target_ip, dst_ip, packet_dst)
	if packet_dst ~= byteorder.hton32(dst_ip) then
		return false
	end

	local rewritten = false
	local srcport = byteorder.ntoh16(skb:getuint16(thoff))
	if srcport == dns then
		local dnsoff = thoff + 8
		local nanswers = byteorder.ntoh16(skb:getuint16(dnsoff + 6))

		-- check the domain name
		dnsoff = dnsoff + 12
		local domainname, nameoff = get_domain(skb, dnsoff)
		if domainname == target_dns then
			dnsoff = dnsoff + nameoff + 4 -- skip over type, label fields
			-- iterate over answers
			for _ = 1, nanswers do
				local atype = byteorder.hton16(skb:getuint16(dnsoff + 2))
				if atype == 1 then
					skb:setuint32(dnsoff + 12, byteorder.hton32(target_ip))
					rewritten = true
				end
				dnsoff = dnsoff + 16
			end
		end
	end

	return rewritten
end

local function dnsdoctor_hook(skb)
	local pkt = skb:data("net")
	local ihl = pkt:getuint8(0) & 0x0F
	local thoff = ihl * 4
	local proto = pkt:getuint8(9)
	local packet_dst = pkt:getuint32(16)

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

	if doctor(pkt, thoff, target_dns, target_ip, dst_ip, packet_dst) then
		skb:checksum()
	end
	return action.ACCEPT
end

netfilter.register{
	hook = dnsdoctor_hook,
	pf = family.INET,
	hooknum = hooks.PRE_ROUTING,
	priority = pri.MANGLE + 1,
}

