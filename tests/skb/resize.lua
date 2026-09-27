--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the resize test (see resize.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")

local PRIORITY <const> = 0x12360000 -- resize.sh's socat priorities are PRIORITY + 1 to 5
local PAYLOAD  <const> = 2048
local DELTA    <const> = 16
local HEAD     <const> = 20 -- an IPv4 header, shorter than the TCP/IP headers in the linear head
local OVERGROW <const> = 65536 -- more than any head holds past its tail

local cases = {}

function cases.shrink(len)
	return len - DELTA
end

function cases.head()
	return HEAD
end

function cases.grow(len)
	return len + DELTA
end

function cases.overgrow(len)
	return len + OVERGROW
end

cases.linear = cases.shrink

local refusals = {
	overgrow = "insufficient tailroom",
}

local pending = {
	[PRIORITY + 1] = "shrink",
	[PRIORITY + 2] = "head",
	[PRIORITY + 3] = "grow",
	[PRIORITY + 4] = "overgrow",
	[PRIORITY + 5] = "linear",
}

local function verdict(skb, name, want, ok, err)
	local refusal = refusals[name]
	if refusal ~= nil then
		return (not ok and err:find(refusal, 1, true)) and "ok" or ("FAIL did not refuse: " .. tostring(err))
	elseif not ok then
		return "FAIL " .. err
	end
	local len, datalen = #skb, #skb:data()
	if len ~= want or datalen ~= want then
		return "FAIL length " .. len .. ", data " .. datalen .. ", want " .. want
	end
	return "ok"
end

local function resize_hook(skb)
	local priority = skb:priority()
	local name = pending[priority]
	local len = #skb
	if name == nil or len < PAYLOAD then
		return nf.action.ACCEPT
	end
	pending[priority] = nil
	local want = cases[name](len)
	local ok, err = pcall(skb.resize, skb, want)
	print("skb resize: " .. name .. " " .. verdict(skb, name, want, ok, err))
	return nf.action.DROP
end

netfilter.register{
	hook     = resize_hook,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
}

