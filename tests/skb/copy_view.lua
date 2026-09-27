--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the copy_view test (see copy_view.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")

local MARK      <const> = 1275 -- MARK in copy_view.sh
local ICMP_TYPE <const> = 20 -- past an IPv4 header without options, as ping sends it
local ECHO      <const> = 8

local order = {"plain", "held", "kept", "first", "last", "stop"}
local steps = {}
local views = {}
local step = 0
local copy
local expected

local function report(cell, failure)
	print("skb copy view: " .. cell .. (failure and " FAIL " .. failure or " ok"))
end

local function release(_, cell)
	local read = views[cell]:getstring(0)
	views[cell] = nil
	collectgarbage()
	if read ~= expected then
		return string.format("read %d bytes, not the %d the copy held", #read, #expected)
	end
end

function steps.plain(skb)
	skb:copy()
	collectgarbage()
end

function steps.held(skb)
	copy = skb:copy()
	copy:data()
	collectgarbage()
end

function steps.kept()
	views.first, views.last = copy:data(), copy:data()
	expected = views.first:getstring(0)
	copy = nil
	collectgarbage()
end

steps.first = release
steps.last = release

function steps.stop(skb)
	views.stop = skb:copy():data()
	collectgarbage()
end

local function hook(skb)
	if skb:data():getuint8(ICMP_TYPE) ~= ECHO then
		return nf.action.ACCEPT
	end
	step = step + 1
	local cell = order[step]
	report(cell, steps[cell](skb, cell))
	return nf.action.ACCEPT
end

netfilter.register{
	hook     = hook,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
	mark     = MARK,
}

