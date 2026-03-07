--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local nf        = require("netfilter")
local byteorder = require("byteorder")

local TCP  = 6
local PORT = 8080

local function http_forge(skb)
	local pkt   = skb:data()
	local proto = pkt:getuint8(9)
	if proto == TCP then
		local ihl      = (pkt:getuint8(0) & 0x0F) * 4
		local sport    = byteorder.ntoh16(pkt:getuint16(ihl))
		if sport == PORT then
			local tcp_off  = (pkt:getuint8(ihl + 12) >> 4) * 4
			local http_off = ihl + tcp_off
			if pkt:getstring(http_off, 5) == "HTTP/" then
				-- "HTTP/1.1 " is 9 bytes; overwrite 3-digit status code
				pkt:setstring(http_off + 9, "403")
				print("http_forge: forged 403 Forbidden response")
				skb:checksum()
			end
		end
	end
	return nf.action.ACCEPT
end

nf.register{
	hook     = http_forge,
	pf       = nf.family.INET,
	hooknum  = nf.inet_hooks.LOCAL_OUT,
	priority = nf.ip_priority.FILTER,
}

