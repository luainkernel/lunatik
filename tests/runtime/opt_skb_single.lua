--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the opt_skb_single regression test (see opt_skb_single.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local family    = nf.proto
local action    = nf.action
local hooks     = nf.inet
local priority  = nf.ip.pri
local lunatik   = require("lunatik")

local triggered = false

local function refuses(key, what, object)
	local ok, err = pcall(function() lunatik._ENV[key] = object end)
	if ok then
		lunatik._ENV[key] = nil -- not left behind: a shared view would hold its module past the test
	end
	assert(not ok and err:find("cannot share SINGLE object"),
		"expected SINGLE rejection for " .. what .. ": " .. tostring(err))
end

local function hook(skb)
	if triggered then
		return action.ACCEPT
	end
	triggered = true

	refuses("opt_skb_single", "skb", skb)
	refuses("opt_data_single", "skb:data()", skb:data())
	refuses("opt_copy_single", "skb:copy():data()", skb:copy():data())

	return action.ACCEPT
end

netfilter.register{
	hook     = hook,
	pf       = family.INET,
	hooknum  = hooks.LOCAL_OUT,
	priority = priority.FILTER,
}

