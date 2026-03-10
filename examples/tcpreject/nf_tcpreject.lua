--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Inject a TCP RST toward the origin for forwarded packets matching a mark.
-- Use nft to mark packets before this hook runs (priority mangle < filter).

local netfilter = require("netfilter")
local byteorder = require("byteorder")
local family    = netfilter.family
local action    = netfilter.action
local hooks     = netfilter.inet_hooks
local priority  = netfilter.ip_priority

local IP_TOTLEN  = 2
local IP_SADDR   = 12
local IP_DADDR   = 16

local TCP_SPORT  = 0
local TCP_DPORT  = 2
local TCP_SEQ    = 4
local TCP_ACK    = 8
local TCP_DOFF   = 12
local TCP_FLAGS  = 13
local TCP_URGENT = 18
local TCP_HDRLEN = 20

local RST   = 0x04
local ACK   = 0x10
local DOFF5 = 0x50  -- data offset = 5 (20 bytes, no options)

local function swap_addrs(npkt, nframe, ihl)
	local saddr = npkt:getuint32(IP_SADDR)
	local daddr = npkt:getuint32(IP_DADDR)
	npkt:setuint32(IP_SADDR, daddr)
	npkt:setuint32(IP_DADDR, saddr)

	local sport  = npkt:getuint16(ihl + TCP_SPORT)
	local dportn = npkt:getuint16(ihl + TCP_DPORT)
	npkt:setuint16(ihl + TCP_SPORT, dportn)
	npkt:setuint16(ihl + TCP_DPORT, sport)

	local dst_hi = nframe:getuint32(0)
	local dst_lo = nframe:getuint16(4)
	local src_hi = nframe:getuint32(6)
	local src_lo = nframe:getuint16(10)
	nframe:setuint32(0, src_hi)
	nframe:setuint16(4, src_lo)
	nframe:setuint32(6, dst_hi)
	nframe:setuint16(10, dst_lo)
end

local function set_rst(npkt, ihl)
	local seq  = byteorder.ntoh32(npkt:getuint32(ihl + TCP_SEQ))
	local ackn = npkt:getuint32(ihl + TCP_ACK)
	npkt:setuint32(ihl + TCP_SEQ, ackn)
	npkt:setuint32(ihl + TCP_ACK, byteorder.hton32(seq + 1))
	npkt:setuint8(ihl + TCP_DOFF, DOFF5)
	npkt:setuint8(ihl + TCP_FLAGS, RST | ACK)
	npkt:setuint16(ihl + TCP_URGENT, 0)
end

local function tcpreject(skb)
	local pkt = skb:data("net")
	local ihl = (pkt:getuint8(0) & 0x0F) * 4

	local nskb   = skb:copy()
	local nframe = nskb:data("mac")
	local npkt   = nskb:data("net")

	swap_addrs(npkt, nframe, ihl)
	set_rst(npkt, ihl)

	local rst_len = ihl + TCP_HDRLEN
	nskb:resize(rst_len)
	npkt:setuint16(IP_TOTLEN, byteorder.hton16(rst_len))

	nskb:checksum()
	nskb:forward()
	return action.DROP
end

netfilter.register{
	hook     = tcpreject,
	pf       = family.INET,
	hooknum  = hooks.FORWARD,
	priority = priority.FILTER,
	mark     = 0x403,
}

