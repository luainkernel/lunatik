--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu netfilter test, registration after load (see percpu_netfilter.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local nfcount   = require("tests.runtime.nfcount")

local function accept(skb)
	return nf.action.ACCEPT
end

local late = {
	hook     = accept,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
}

local function register_late(skb)
	local ok, err = pcall(netfilter.register, late)
	print("percpu netfilter late: " .. tostring(ok and "registered" or err))
	return nf.action.ACCEPT
end

netfilter.register(nfcount.localin(register_late, nfcount.MARK))

