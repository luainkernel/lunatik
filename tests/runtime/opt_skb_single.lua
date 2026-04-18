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

local function hook(skb)
	if triggered then
		return action.ACCEPT
	end
	triggered = true

	local ok, err = pcall(function()
		lunatik._ENV["opt_skb_single"] = skb
	end)
	assert(not ok and err:find("cannot share SINGLE object"),
		"expected SINGLE rejection for skb: " .. tostring(err))

	local ok2, err2 = pcall(function()
		lunatik._ENV["opt_data_single"] = skb:data()
	end)
	assert(not ok2 and err2:find("cannot share SINGLE object"),
		"expected SINGLE rejection for skb:data(): " .. tostring(err2))

	return action.ACCEPT
end

netfilter.register{
	hook     = hook,
	pf       = family.INET,
	hooknum  = hooks.LOCAL_OUT,
	priority = priority.FILTER,
}

