--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu netfilter test, a packet during creation (see percpu_netfilter.sh).

local lunatik   = require("lunatik")
local netfilter = require("netfilter")
local nf        = require("linux.nf")

local MARK <const> = 208
local SPIN <const> = 100000000

local env = lunatik._ENV
local key = "nf_percpu:" .. lunatik.cpu()

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

print("percpu netfilter early: armed")

for _ = 1, SPIN do end -- widen the gap between arming the hook and publishing this instance

