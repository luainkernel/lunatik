--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink channel test (see channel.sh).
-- Runs in a softirq runtime: registers a generic netlink multicast family and a
-- LOCAL_OUT netfilter hook that broadcasts from softirq on every packet.

local netlink   = require("netlink")
local netfilter = require("netfilter")
local nf        = require("linux.nf")

local chan = netlink.channel("lunatiktest")

local function channel_hook(skb)
	chan:broadcast("netlink channel: ok")
	return nf.action.ACCEPT
end

netfilter.register{
	hook     = channel_hook,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
}

