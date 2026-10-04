--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the connmark test (see connmark.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local byteorder = require("byteorder")
local ipproto   = require("linux.socket").ipproto

local IP_PROTO     <const> = 9
local UDP_DPORT    <const> = 2
local PORT         <const> = 5562   -- tracked flow
local PORT_NOTRACK <const> = 5563   -- notrack'd flow (no conntrack)

local DSCP_MASK <const> = 0xfe000000
local DSCP_VAL  <const> = 0xba000000
local LOW_MASK  <const> = 0x000000ff
local LOW_VAL   <const> = 0x000000ab
local U32_MAX   <const> = 0xffffffff

local OUTOFBOUNDS <const> = "out of bounds"

local refused <const> = {-1, U32_MAX + 1, (1 << 32) | LOW_VAL}

local function refuses(skb, value)
	local ok, err = pcall(skb.connmark, skb, value)
	return not ok and err:find(OUTOFBOUNDS, 1, true) ~= nil
end

-- connmark(value) overwrites and returns the new mark; connmark() and connmark(nil) read it.
-- Masked updates are composed in Lua. This exercises the smallest and the largest mark,
-- an overwrite, refusals past 32 bits that keep the mark, a masked set that preserves
-- out-of-mask bits, and a clear. Ends at DSCP_VAL.
local function tracked_seq(skb)
	if skb:connmark(0) ~= 0 or skb:connmark(U32_MAX) ~= U32_MAX then
		print("connmark: tracked FAIL ends")
		return
	end
	if skb:connmark(LOW_VAL) ~= LOW_VAL then
		print("connmark: tracked FAIL set")
		return
	end
	if skb:connmark(nil) ~= LOW_VAL or skb:connmark() ~= LOW_VAL then
		print("connmark: tracked FAIL nil")
		return
	end
	for _, value in ipairs(refused) do
		if not refuses(skb, value) or skb:connmark() ~= LOW_VAL then
			print("connmark: tracked FAIL bound")
			return
		end
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

-- Without conntrack, connmark returns nil for both read and write, and still refuses a value past 32 bits.
local function notrack_seq(skb)
	if skb:connmark(DSCP_VAL) == nil and skb:connmark() == nil and refuses(skb, U32_MAX + 1) then
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

