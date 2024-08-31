--
-- SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Filter DNS packets based on a blocklist

local xt = require("xtable")
local nf = require("netfilter")
local common = require("examples.dnsblock.common")
local family = nf.family

local function nop() end

local function dnsblock_mt(skb, par)
	local thoff = par.thoff
	local proto = skb:getuint8(9)

	return common.hook(skb, thoff, proto)
end

xt.match{
	name = "dnsblock",
	revision = 1,
	family = family.UNSPEC,
	proto = 0,
	match = dnsblock_mt,
	checkentry = nop,
	destroy = nop,
	hooks = 0,
}

