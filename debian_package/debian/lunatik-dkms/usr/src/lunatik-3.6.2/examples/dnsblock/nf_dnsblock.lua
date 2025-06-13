--
-- SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Filter DNS packets based on a blocklist using new netfilter hooks

local nf = require("netfilter")
local common = require("examples.dnsblock.common")
local family = nf.family
local action = nf.action
local hooks = nf.inet_hooks
local priority = nf.ip_priority

local function dnsblock_hook(skb)
	local proto = skb:getuint8(9)
	local ihl = (skb:getuint8(0) & 0x0F)
	local thoff = ihl * 4

	return common.hook(skb, thoff, proto) and action.DROP or action.ACCEPT
end

nf.register{
	hook = dnsblock_hook,
	pf = family.INET,
	hooknum = hooks.LOCAL_OUT,
	priority = priority.FILTER,
}

