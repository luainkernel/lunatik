--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the runtime refcnt leak regression test (see refcnt_leak.sh).

local netfilter = require("netfilter")
local family    = require("linux.nfproto")
local action    = netfilter.action
local hooks     = require("linux.nf_inet")
local priority  = require("linux.nf_ip_pri")

local function hook(skb)
	return action.ACCEPT
end

netfilter.register{
	hook     = hook,
	pf       = family.INET,
	hooknum  = hooks.FORWARD,
	priority = priority.FILTER,
	mark     = 0,
}

error("intentional error after first register")

