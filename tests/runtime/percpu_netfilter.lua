--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu netfilter test (see percpu_netfilter.sh).

local lunatik   = require("lunatik")
local netfilter = require("netfilter")
local nf        = require("linux.nf")

local MARK <const> = 208

local env = lunatik._ENV
local key = "nf_percpu:" .. tostring(lunatik.cpu() or "plain")

local function count(skb)
	env[key] = (env[key] or 0) + 1
	return nf.action.ACCEPT
end

netfilter.register{
	hook     = count,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_IN,
	priority = nf.ip.pri.FILTER,
	mark     = MARK,
}

