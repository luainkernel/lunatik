--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu refusal test (see percpu_refuse.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")

local family   = nf.proto
local action   = nf.action
local hooks    = nf.inet
local priority = nf.ip.pri

local function accept(skb)
	return action.ACCEPT
end

netfilter.register{
	hook     = accept,
	pf       = family.INET,
	hooknum  = hooks.LOCAL_IN,
	priority = priority.FILTER,
}

