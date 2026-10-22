--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netfilter mark test (see mark.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local byteorder = require("byteorder")
local net       = require("net")
local hooks     = require("tests.netfilter.hooks")

local PREFIX <const> = "netfilter mark: "
local LENGTH <const> = 84 -- an IPv4 header and the 64 bytes of ICMP of a ping
local DADDR  <const> = 16 -- the destination address in an IPv4 header
local TARGET <const> = net.aton("127.0.0.225") -- TARGET in mark.sh
local MARK   <const> = 225 -- MARK in mark.sh: 1 in the LOW field and 0xe in the HIGH one
local LOW    <const> = 0x0f
local HIGH   <const> = 0xf0
local SET    <const> = 0x3c -- 3 for the HIGH field, and bits outside it the mask drops
local FILTER <const> = nf.ip.pri.FILTER

local function pinged(skb)
	return #skb == LENGTH and byteorder.ntoh32(skb:data():getuint32(DADDR)) == TARGET -- length first: data() linearizes
end

local function report(skb, name)
	if pinged(skb) then
		print(PREFIX .. name .. " " .. skb:mark())
	end
	return nf.action.ACCEPT
end

local function absent(skb)
	return report(skb, "absent")
end

local function zero(skb)
	return report(skb, "zero")
end

local function field(skb)
	return report(skb, "field")
end

local function masked(skb)
	return report(skb, "masked")
end

local function set(skb)
	if pinged(skb) then
		return nf.action.ACCEPT, SET
	end
	return nf.action.ACCEPT
end

local function after(skb)
	return report(skb, "after")
end

netfilter.register(hooks.localout(absent))
netfilter.register(hooks.localout(zero, 0))
netfilter.register(hooks.localout(field, MARK & LOW, LOW))
netfilter.register(hooks.localout(masked, nil, LOW))
netfilter.register(hooks.localout(set, MARK & HIGH, HIGH, FILTER + 1)) -- past the hooks that read the ping's own mark
netfilter.register(hooks.localout(after, nil, nil, FILTER + 2)) -- past the one that sets it

