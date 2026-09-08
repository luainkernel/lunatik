--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu refcnt leak test (see refcnt_leak.sh):
-- every runtime registers a hook and the last one errors, so the rollback
-- has hooks of earlier runtimes to release.

local lunatik   = require("lunatik")
local linux     = require("linux")
local netfilter = require("netfilter")
local nf        = require("linux.nf")

local function hook(skb)
	return nf.action.ACCEPT
end

netfilter.register{
	hook     = hook,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.FORWARD,
	priority = nf.ip.pri.FILTER,
	mark     = 0,
}

if lunatik.cpu() == linux.numcpus() - 1 then
	error("intentional error on the last runtime")
end

