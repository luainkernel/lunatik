--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the data test (see data.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local ipproto   = require("linux.socket").ipproto

local IP_PROTO   <const> = 9
local OUTER_HLEN <const> = 20 -- the outer IPv4 header, which the MAC header sits past
local TRUNCATED  <const> = 10 -- shorter than the outer IPv4 header
local MARK       <const> = 1278 -- MARK in data.sh

local kept = {}

local function report(cell, ok, format, ...)
	print("skb data: " .. cell .. (ok and " ok" or " FAIL " .. string.format(format, ...)))
end

local function refuses(skb, cell, refusal)
	local ok, err = pcall(skb.data, skb, "mac")
	if ok then -- the view is never read: its size is what the refusal is for
		report(cell, false, "a view")
	else
		report(cell, err:find(refusal, 1, true), "%s", err)
	end
end

local function ends(skb)
	local len, net, mac = #skb, #skb:data(), #skb:data("mac")
	report("tail", net == len and mac == len - OUTER_HLEN, "skb %d, net view %d, mac view %d", len, net, mac)
end

local function layers(skb, cell)
	local net, mac = skb:data(), skb:data("mac")
	local len, netlen, maclen, proto = #skb, #net, #mac, net:getuint8(IP_PROTO)
	report(cell, netlen == len and maclen == len - OUTER_HLEN and proto == ipproto.IPIP,
		"skb %d, net view %d, mac view %d, net protocol %d", len, netlen, maclen, proto)
	return net, mac
end

local function cleared(cell, net, mac)
	local netlen, maclen = #net, #mac -- not read: a view left set points into a packet that is gone
	report(cell, netlen == 0 and maclen == 0, "net view %d, mac view %d", netlen, maclen)
end

local function hook(skb)
	if kept.net then
		cleared("cleared", kept.net, kept.mac)
		collectgarbage() -- frees the copy the outer packet's callback dropped
		cleared("collected", kept.copynet, kept.copymac)
		kept = {}
	end
	if skb:data():getuint8(IP_PROTO) ~= ipproto.IPIP then
		refuses(skb, "unset", "MAC header not set")
		return nf.action.ACCEPT
	end
	ends(skb)
	kept.net, kept.mac = layers(skb, "layers")
	kept.copynet, kept.copymac = layers(skb:copy(), "copy")
	skb:resize(TRUNCATED)
	refuses(skb, "past", "MAC header past the tail")
	return nf.action.DROP
end

netfilter.register{
	hook     = hook,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
	mark     = MARK,
}

