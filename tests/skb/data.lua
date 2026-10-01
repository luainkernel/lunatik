--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the data test (see data.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local ipproto   = require("linux.socket").ipproto

local IP_PROTO   <const> = 9
local ETH_HLEN   <const> = 14 -- the Ethernet header of a frame lo received
local OUTER_HLEN <const> = 20 -- the outer IPv4 header, which the MAC header sits past
local TRUNCATED  <const> = 10 -- shorter than the outer IPv4 header
local MARK       <const> = 1278 -- MARK in data.sh

local kept = {}

local function report(cell, ok, format, ...)
	print("skb data: " .. cell .. (ok and " ok" or " FAIL " .. string.format(format, ...)))
end

local function absent(skb, cell)
	report(cell, skb:data("mac") == nil, "a view")
end

local function ends(skb)
	local len, data, net, mac = #skb, #skb:data(), #skb:data("net"), #skb:data("mac")
	report("tail", data == len and net == len and mac == len - OUTER_HLEN,
		"skb %d, view %d, net view %d, mac view %d", len, data, net, mac)
end

local function layers(skb, cell)
	local data, net, mac = skb:data(), skb:data("net"), skb:data("mac")
	local len, datalen, netlen, maclen, proto = #skb, #data, #net, #mac, net:getuint8(IP_PROTO)
	report(cell, data ~= net and datalen == len and netlen == len and maclen == len - OUTER_HLEN and
		proto == ipproto.IPIP, "skb %d, view %d, net view %d, mac view %d, net protocol %d, " ..
		"data() is the net view %s", len, datalen, netlen, maclen, proto, data == net)
	return {data, net, mac}
end

local function cleared(cell, views)
	-- not read: a view left set points into a packet that is gone
	local data, net, mac = #views[1], #views[2], #views[3]
	report(cell, data == 0 and net == 0 and mac == 0, "view %d, net view %d, mac view %d", data, net, mac)
end

local function received(skb)
	local len, mac = #skb, #skb:data("mac")
	report("received", mac == len + ETH_HLEN, "skb %d, mac view %d", len, mac)
	return nf.action.ACCEPT
end

local function sent(skb)
	if kept.views then
		cleared("cleared", kept.views)
		collectgarbage() -- frees the copy the outer packet's callback dropped
		cleared("collected", kept.copy)
		kept = {}
	end
	if skb:data():getuint8(IP_PROTO) ~= ipproto.IPIP then
		absent(skb, "unset")
		return nf.action.ACCEPT
	end
	ends(skb)
	kept.views = layers(skb, "layers")
	kept.copy = layers(skb:copy(), "copy")
	skb:resize(TRUNCATED)
	absent(skb, "past")
	return nf.action.DROP
end

local function register(hook, hooknum)
	netfilter.register{
		hook     = hook,
		pf       = nf.proto.INET,
		hooknum  = hooknum,
		priority = nf.ip.pri.FILTER,
		mark     = MARK,
	}
end

register(sent, nf.inet.LOCAL_OUT)
register(received, nf.inet.PRE_ROUTING)

