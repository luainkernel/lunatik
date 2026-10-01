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

netfilter.register(hooks.localout(absent))
netfilter.register(hooks.localout(zero, 0))

