--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu netfilter test, duplicate registration (see percpu_netfilter.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")

local function accept(skb)
	return nf.action.ACCEPT
end

local hook = {
	hook     = accept,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_IN,
	priority = nf.ip.pri.FILTER,
}

netfilter.register(hook)
netfilter.register(hook)

