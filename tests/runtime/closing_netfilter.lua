--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Softirq script for the closing test (see closing.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local verdict   = require("tests.runtime.verdict")

local PREFIX <const> = "closing test: "

local function accept(skb)
	return nf.action.ACCEPT
end

local hook = {
	hook     = accept,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
}

local function register()
	verdict.report(PREFIX, "netfilter", pcall(netfilter.register, hook))
end

sentinel = setmetatable({}, {__gc = register})

