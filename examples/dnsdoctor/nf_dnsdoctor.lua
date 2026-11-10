--
-- SPDX-FileCopyrightText: (c) 2024-2026 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- DNS Doctoring using the netfilter API

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local byteorder = require("byteorder")
local net       = require("net")
local action    = nf.action
local family    = nf.proto
local hooks     = nf.inet
local pri       = nf.ip.pri
local ntoh16    = byteorder.ntoh16

local UDP <const> = 0x11
local DNS <const> = 0x35
local IHL <const> = 0x0F
local UDPLEN <const> = 8
local QTAIL <const> = 4
local COMPRESSED <const> = 0xC0
local TYPE_A <const> = 1
local ADDRLEN <const> = 4
local DOMAIN <const> = string.pack("s1s1", "lunatik", "com")
local TARGET <const> = byteorder.hton32(net.aton("10.1.2.3"))
local CLIENT <const> = byteorder.hton32(net.aton("10.1.1.2"))

local ip        = {protocol = 9, daddr = 16}
local dnsheader = {ancount = 6, length = 12}
local answer    = {type = 2, rdlength = 10, rdata = 12}

local function question(pkt, off)
	local name = pkt:getstring(off):match("^[^\0]*")
	return name, off + #name + 1 + QTAIL
end

local function rewrite(pkt, off, count)
	local rewritten = false
	for _ = 1, count do
		if pkt:getuint8(off) & COMPRESSED ~= COMPRESSED then
			break
		end
		local rdlength = ntoh16(pkt:getuint16(off + answer.rdlength))
		if ntoh16(pkt:getuint16(off + answer.type)) == TYPE_A and rdlength == ADDRLEN then
			pkt:setuint32(off + answer.rdata, TARGET)
			rewritten = true
		end
		off = off + answer.rdata + rdlength
	end
	return rewritten
end

local function doctor(pkt, thoff)
	if ntoh16(pkt:getuint16(thoff)) ~= DNS then
		return false
	end
	local dnsoff = thoff + UDPLEN
	local name, answers = question(pkt, dnsoff + dnsheader.length)
	return name == DOMAIN and rewrite(pkt, answers, ntoh16(pkt:getuint16(dnsoff + dnsheader.ancount)))
end

local function dnsdoctor_hook(skb)
	local pkt = skb:data("net")
	local thoff = (pkt:getuint8(0) & IHL) * 4
	if pkt:getuint8(ip.protocol) == UDP and pkt:getuint32(ip.daddr) == CLIENT and doctor(pkt, thoff) then
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

