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
local TRIM      <const> = 1

local order = {"plain", "held", "again", "dropped", "stop"}
local steps = {}
local views = {}
local step = 0
local copy

local function report(cell, failure)
	print("skb copy view: " .. cell .. (failure and " FAIL " .. failure or " ok"))
end

function steps.plain(skb)
	skb:copy()
	collectgarbage()
end

function steps.held(skb)
	copy = skb:copy()
	local expected = copy:data():getstring(0)
	collectgarbage()
	views.held = copy:data()
	local read = views.held:getstring(0)
	if read ~= expected then
		return string.format("read %d bytes, not the %d the copy held", #read, #expected)
	end
end

function steps.again()
	copy:resize(#copy - TRIM)
	views.again = copy:data()
	if views.again ~= views.held then
		return "a second data() call returned another object"
	end
	local len, held = #copy, #views.held
	if held ~= len then
		return string.format("a view of %d bytes, of a copy of %d", held, len)
	end
end

function steps.dropped()
	copy = nil
	collectgarbage()
	local length = #views.held
	if length ~= 0 then -- not read: the copy it views may be gone
		return string.format("a view of %d bytes", length)
	end
	local ok, err = pcall(views.held.getuint8, views.held, 0)
	views.held, views.again = nil, nil
	collectgarbage()
	if ok or not err:find("out of bounds", 1, true) then
		return ok and "a read" or err
	end
end

function steps.stop(skb)
	copy = skb:copy()
	views.stop = copy:data()
	collectgarbage()
end

local function hook(skb)
	if skb:data():getuint8(ICMP_TYPE) ~= ECHO then
		return nf.action.ACCEPT
	end
	step = step + 1
	local cell = order[step]
	report(cell, steps[cell](skb))
	return nf.action.ACCEPT
end

netfilter.register{
	hook     = hook,
	pf       = nf.proto.INET,
	hooknum  = nf.inet.LOCAL_OUT,
	priority = nf.ip.pri.FILTER,
	mark     = MARK,
}

