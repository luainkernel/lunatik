--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the copy_offload test (see copy_offload.sh).

local filter  = require("tests.skb.filter")
local nf      = require("linux.nf")
local ipproto = require("linux.socket").ipproto

local IP_PROTO     <const> = 9
local OFFLOAD_MARK <const> = 1320 -- OFFLOAD_MARK in copy_offload.sh
local PLAIN_MARK   <const> = 1321 -- PLAIN_MARK in copy_offload.sh
local REFUSAL      <const> = "copy would leave unencrypted"
local PAST         <const> = "MAC header past the data"
local UNSET        <const> = "MAC header not set"

local function report(cell, failure)
	print("skb copy offload: " .. cell .. (failure and " FAIL " .. failure or " ok"))
end

local function carries(skb, proto)
	return skb:data():getuint8(IP_PROTO) == proto
end

local function raises(name, skb, want)
	local ok, err = pcall(skb.forward, skb)
	if ok then
		return name .. ": a clone was sent"
	elseif not err:find(want, 1, true) then
		return name .. ": " .. err
	end
end

local function copied(skb, want)
	return raises("copy", skb:copy(), want)
end

local function offloaded(skb)
	if not carries(skb, ipproto.ESP) then
		return nf.action.ACCEPT
	end
	report("offloaded", copied(skb, REFUSAL) or raises("packet", skb, PAST))
	return nf.action.DROP
end

local function plain(skb)
	if not carries(skb, ipproto.ICMP) then
		return nf.action.ACCEPT
	end
	report("plain", copied(skb, UNSET))
	return nf.action.DROP
end

filter.register(offloaded, nf.proto.IPV4, nf.inet.POST_ROUTING, OFFLOAD_MARK)
filter.register(plain, nf.proto.IPV4, nf.inet.POST_ROUTING, PLAIN_MARK)

