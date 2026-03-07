--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local nf        = require("netfilter")
local byteorder = require("byteorder")

local TCP  = 6
local PORT = 7777

local RST = 0x04
local ACK = 0x10

local function tcp_rst(skb)
	local pkt   = skb:data()
	local proto = pkt:getuint8(9)
	if proto == TCP then
		local ihl   = (pkt:getuint8(0) & 0x0F) * 4
		local dport = byteorder.ntoh16(pkt:getuint16(ihl + 2))
		if dport == PORT then
			-- swap TCP ports so the RST goes back to the sender
			local sport = pkt:getuint16(ihl)
			pkt:setuint16(ihl,     pkt:getuint16(ihl + 2))
			pkt:setuint16(ihl + 2, sport)
			-- ack = incoming seq + 1
			local seq = byteorder.ntoh32(pkt:getuint32(ihl + 4))
			pkt:setuint32(ihl + 4, 0)
			pkt:setuint32(ihl + 8, byteorder.hton32(seq + 1))
			-- set RST+ACK flags
			pkt:setuint8(ihl + 13, RST | ACK)
			print("tcp_rst: sending RST to port " .. PORT)
			skb:checksum()
			skb:forward()
			return nf.action.DROP
		end
	end
	return nf.action.ACCEPT
end

nf.register{
	hook     = tcp_rst,
	pf       = nf.family.INET,
	hooknum  = nf.inet_hooks.LOCAL_IN,
	priority = nf.ip_priority.FILTER,
}

