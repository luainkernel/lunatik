--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local netfilter = require("netfilter")
local nf        = require("linux.nf")

local family   = nf.proto
local action   = nf.action
local hooks    = nf.inet
local priority = nf.ip.pri

local quarantined

local function verdict(skb)
	if not quarantined then
		return action.ACCEPT
	end
	local idx = skb:ifindex()
	if idx and quarantined[tostring(idx)] then
		return action.DROP
	end
	return action.ACCEPT
end

netfilter.register{
	hook     = verdict,
	pf       = family.INET,
	hooknum  = hooks.PRE_ROUTING,
	priority = priority.RAW,
}

netfilter.register{
	hook     = verdict,
	pf       = family.INET,
	hooknum  = hooks.POST_ROUTING,
	priority = priority.RAW,
}

local function attacher(shared)
	quarantined = shared
end
return attacher

