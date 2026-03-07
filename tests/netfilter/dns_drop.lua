--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local nf        = require("netfilter")
local byteorder = require("byteorder")

local UDP = 0x11
local DNS = 53

local function dns_drop(skb)
	local pkt   = skb:data()
	local proto = pkt:getuint8(9)
	if proto == UDP then
		local ihl   = (pkt:getuint8(0) & 0x0F) * 4
		local dport = byteorder.ntoh16(pkt:getuint16(ihl + 2))
		if dport == DNS then
			print("dns_drop: dropping DNS query")
			return nf.action.DROP
		end
	end
	return nf.action.ACCEPT
end

nf.register{
	hook     = dns_drop,
	pf       = nf.family.INET,
	hooknum  = nf.inet_hooks.LOCAL_OUT,
	priority = nf.ip_priority.FILTER,
}

