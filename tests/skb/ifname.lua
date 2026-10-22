--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the ifname test (see ifname.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")

local TAG     <const> = "lunatik ifname " -- TAG in ifname.sh
local PAYLOAD <const> = 28 -- an IPv4 and a UDP header

local function ifname_hook(skb)
	local data = skb:data()
	if #data < PAYLOAD + #TAG or data:getstring(PAYLOAD, #TAG) ~= TAG then
		return nf.action.ACCEPT
	end
	print("skb ifname: " .. data:getstring(PAYLOAD + #TAG) .. " " .. tostring(skb:ifname()))
	return nf.action.DROP
end

netfilter.register{
	hook     = ifname_hook,
	pf       = nf.proto.BRIDGE,
	hooknum  = nf.br.PRE_ROUTING,
	priority = nf.br.pri.FILTER_BRIDGED,
}

netfilter.register{
	hook     = ifname_hook,
	pf       = nf.proto.IPV4,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
}

