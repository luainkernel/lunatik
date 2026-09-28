--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the copy test (see copy.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local linux     = require("linux")

local IFACE        <const> = "lunatikcopy0" -- IFACE in copy.sh
local SEGMENT      <const> = 1000 -- SEGMENT in copy.sh
local SEGMENTS     <const> = 8    -- SEGMENTS in copy.sh
local GSO_SEGMENTS <const> = 4    -- GSO_SEGMENTS in copy.sh
local HEADERS      <const> = 28   -- an IPv4 and a UDP header
local REFUSAL      <const> = "FRAGLIST GSO skbs cannot be copied"

local ifindex = linux.ifindex(IFACE)

local cases = {
	[HEADERS + SEGMENT * SEGMENTS]     = "fraglist",
	[HEADERS + SEGMENT]                = "plain",
	[HEADERS + SEGMENT * GSO_SEGMENTS] = "gso",
}

local verdicts = {}

function verdicts.fraglist(skb, ok, err)
	if ok then
		return "FAIL copied"
	end
	return err:find(REFUSAL, 1, true) and "ok" or ("FAIL " .. err)
end

function verdicts.plain(skb, ok, copy)
	if not ok then
		return "FAIL " .. copy
	end
	return #copy == #skb and "ok" or ("FAIL length " .. #copy .. ", want " .. #skb)
end

verdicts.gso = verdicts.plain

local function copy_hook(skb)
	local case = cases[#skb]
	if skb:ifindex() ~= ifindex or case == nil then
		return nf.action.ACCEPT
	end
	local ok, copy = pcall(skb.copy, skb)
	print("skb copy: " .. case .. " " .. verdicts[case](skb, ok, copy))
	return nf.action.DROP
end

netfilter.register{
	hook     = copy_hook,
	pf       = nf.proto.IPV4,
	hooknum  = nf.inet.PRE_ROUTING,
	priority = nf.ip.pri.FILTER,
}

