--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu affinity test (see percpu_affinity.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local byteorder = require("byteorder")
local net       = require("net")
local lunatik   = require("lunatik")

local family    = nf.proto
local action    = nf.action
local hooks     = nf.inet
local priority  = nf.ip.pri

local IP_DADDR <const> = 16
local TARGET   <const> = byteorder.hton32(net.aton("127.0.0.9"))

local counter <const> = "percpu_nf:" .. lunatik.cpu()
local env = lunatik._ENV

local function hook(skb)
	if skb:data():getuint32(IP_DADDR) == TARGET then
		env[counter] = (env[counter] or 0) + 1
	end
	return action.ACCEPT
end

netfilter.register{
	hook     = hook,
	pf       = family.INET,
	hooknum  = hooks.LOCAL_OUT,
	priority = priority.FILTER,
}

