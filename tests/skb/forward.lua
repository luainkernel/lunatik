--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the forward test (see forward.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local ipproto   = require("linux.socket").ipproto

local IP_PROTO    <const> = 9
local ICMP_TYPE   <const> = 20 -- past an IPv4 header without options, as ping sends it
local ECHO        <const> = 8
local PAST_MARK   <const> = 1291 -- PAST_MARK in forward.sh
local BEFORE_MARK <const> = 1292 -- BEFORE_MARK in forward.sh
local AT_MARK     <const> = 1293 -- AT_MARK in forward.sh
local REFUSAL     <const> = "MAC header past the data"

local cells = {[BEFORE_MARK] = "before", [AT_MARK] = "at"}
local forwarded = {}

local function past(skb)
	if skb:data():getuint8(IP_PROTO) ~= ipproto.IPIP then
		return nf.action.ACCEPT
	end
	local ok, err = pcall(skb.forward, skb)
	if ok then
		print("skb forward: past FAIL a clone was sent")
	elseif err:find(REFUSAL, 1, true) then
		print("skb forward: past ok")
	else
		print("skb forward: past FAIL " .. err)
	end
	return nf.action.DROP
end

local function resend(skb)
	local packet = skb:data()
	if packet:getuint8(IP_PROTO) ~= ipproto.ICMP or packet:getuint8(ICMP_TYPE) ~= ECHO then
		return nf.action.ACCEPT
	end
	local cell = cells[skb:mark()]
	if forwarded[cell] then
		print("skb forward: " .. cell .. " ok")
	else
		forwarded[cell] = true
		skb:forward()
	end
	return nf.action.ACCEPT
end

netfilter.register{
	hook     = past,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
	mark     = PAST_MARK,
}

for mark in pairs(cells) do
	netfilter.register{
		hook     = resend,
		pf       = nf.proto.INET,
		hooknum  = nf.inet.PRE_ROUTING,
		priority = nf.ip.pri.FILTER,
		mark     = mark,
	}
end

