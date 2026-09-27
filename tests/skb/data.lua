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

local function refuses(skb, cell, refusal)
	local ok, err = pcall(skb.data, skb, "mac")
	if ok then -- the view is never read: its size is what the refusal is for
		print("skb data: " .. cell .. " FAIL a view")
	elseif err:find(refusal, 1, true) then
		print("skb data: " .. cell .. " ok")
	else
		print("skb data: " .. cell .. " FAIL " .. err)
	end
end

local function ends(skb)
	local len, net, mac = #skb, #skb:data(), #skb:data("mac")
	if net == len and mac == len - OUTER_HLEN then
		print("skb data: tail ok")
	else
		print(string.format("skb data: tail FAIL skb %d, net view %d, mac view %d", len, net, mac))
	end
end

local function hook(skb)
	if skb:data():getuint8(IP_PROTO) ~= ipproto.IPIP then
		refuses(skb, "unset", "MAC header not set")
		return nf.action.ACCEPT
	end
	ends(skb)
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

