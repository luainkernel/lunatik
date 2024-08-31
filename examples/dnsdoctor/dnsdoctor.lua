--
-- SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- DNS Doctoring : Rewrite DNS type A record to a private address for local clients

local xt = require("xtable")
local nf = require("netfilter")
local string = require("string")
local common = require("examples.dnsdoctor.common")
local family = nf.family

local function nop() end

local function dnsdoctor_tg(skb, par, userargs)
	local target_dns, dst_ip, target_ip = string.unpack(">s4I4I4", userargs)
	local thoff = par.thoff

	return common.hook(skb, thoff, target_dns, target_ip, dst_ip)
end

xt.target{
	name = "dnsdoctor",
	revision = 0,
	family = family.UNSPEC,
	proto = 0,
	target = dnsdoctor_tg,
	checkentry = nop,
	destroy = nop,
	hooks = 0,
}

