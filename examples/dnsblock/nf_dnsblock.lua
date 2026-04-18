--
-- SPDX-FileCopyrightText: (c) 2024-2026 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Filter DNS packets based on a blocklist using new netfilter hooks

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local common    = require("examples.dnsblock.common")
local family    = nf.proto
local action    = nf.action
local hooks     = nf.inet
local priority  = nf.ip.pri

local function dnsblock_hook(skb)
	local pkt = skb:data("net")
	local proto = pkt:getuint8(9)
	local ihl = (pkt:getuint8(0) & 0x0F)
	local thoff = ihl * 4

	return common.hook(pkt, thoff, proto) and action.DROP or action.ACCEPT
end

netfilter.register{
	hook = dnsblock_hook,
	pf = family.INET,
	hooknum = hooks.LOCAL_OUT,
	priority = priority.FILTER,
}

