--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the view test (see view.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local set       = require("set")

local MARK <const> = 1915 -- MARK in view.sh

local function sent(skb)
	local ok, err = pcall(set.fromdata, skb:data(), {n = 0, offsets = 0, blob = 0})
	print("set view: " .. ((not ok and err:find("external memory", 1, true)) and "ok" or "FAIL " .. tostring(err)))
	return nf.action.ACCEPT
end

netfilter.register{
	hook     = sent,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
	mark     = MARK,
}

