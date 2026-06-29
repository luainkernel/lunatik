--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink channel test (see channel.sh).

local netlink   = require("netlink")
local netfilter = require("netfilter")
local nf        = require("linux.nf")

local chan = netlink.channel("lunatiktest")

local function channel_hook(skb)
	chan:broadcast("netlink channel: ok")
	return nf.action.ACCEPT
end

-- PRE_ROUTING on received (loopback) traffic runs in NET_RX softirq, so the
-- broadcast is genuinely exercised from softirq context.
netfilter.register{
	hook     = channel_hook,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.PRE_ROUTING,
	priority = nf.ip.pri.FILTER,
}

