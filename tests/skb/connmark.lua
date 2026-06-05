--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the connmark test (see connmark.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local byteorder = require("byteorder")
local ipproto   = require("linux.ipproto")

local IP_PROTO     <const> = 9
local UDP_DPORT    <const> = 2
local PORT         <const> = 5562   -- tracked flow
local PORT_NOTRACK <const> = 5563   -- notrack'd flow (no conntrack)

local DSCP_MASK <const> = 0xfe000000
local DSCP_VAL  <const> = 0xba000000
local LOW_MASK  <const> = 0x000000ff
local LOW_VAL   <const> = 0x000000ab

-- connmark(value) overwrites and returns the new mark; connmark() reads it.
-- Masked updates are composed in Lua. This exercises an overwrite, a masked set
-- that preserves out-of-mask bits, and a clear. Ends at DSCP_VAL.
local function tracked_seq(skb)
	if skb:connmark(LOW_VAL) ~= LOW_VAL then
		print("connmark: tracked FAIL set")
		return
	end
	skb:connmark((skb:connmark() & ~DSCP_MASK) | DSCP_VAL)
	if skb:connmark() ~= (DSCP_VAL | LOW_VAL) then
		print("connmark: tracked FAIL mask")
		return
	end
	skb:connmark(skb:connmark() & ~LOW_MASK)
	if skb:connmark() ~= DSCP_VAL then
		print("connmark: tracked FAIL clear")
		return
	end
	print("connmark: tracked ok")
end

-- Without conntrack, connmark returns nil for both read and write.
local function notrack_seq(skb)
	if skb:connmark(DSCP_VAL) == nil and skb:connmark() == nil then
		print("connmark: notrack ok")
	else
		print("connmark: notrack FAIL")
	end
end

local function connmark_hook(skb)
	local pkt = skb:data()
	if pkt:getuint8(IP_PROTO) == ipproto.UDP then
		local ihl = (pkt:getuint8(0) & 0x0F) * 4
		local dport = byteorder.ntoh16(pkt:getuint16(ihl + UDP_DPORT))
		if dport == PORT then
			tracked_seq(skb)
		elseif dport == PORT_NOTRACK then
			notrack_seq(skb)
		end
	end
	return nf.action.ACCEPT
end

netfilter.register{
	hook     = connmark_hook,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
}

