--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc non-linear test (see test_tc.sh).

local tc     = require("tc")
local data   = require("data")
local action = require("linux.tc").action

local PRIORITY <const> = 0x13690000 -- PRIORITY in test_tc.sh
local PAYLOAD  <const> = 1024 -- PAYLOAD in test_tc.sh
local FILL     <const> = 0x58 -- FILL in test_tc.sh, 'X', the byte the payload is made of
local ETHER    <const> = 14 -- the Ethernet header, which "net" starts past
local HALF     <const> = 2 -- the bytes of a getuint32 on each side of the payload's start
local DELTA    <const> = 16
local REFUSAL  <const> = "skb is not linear"
local READONLY <const> = "read only"
local BOUNDS   <const> = "out of bounds"

local done = false
local kept -- the non-linear skb's view, read again once its callback returned

local function report(cell, ok, format, ...)
	print("tc nonlinear: " .. cell .. (ok and " ok" or " FAIL " .. string.format(format, ...)))
end

local function refuses(skb, method, ...)
	local ok, err = pcall(skb[method], skb, ...)
	report(method, not ok and err:find(REFUSAL, 1, true), "%s", ok and "no refusal" or err)
end

-- whether a write to the view raises "read only"
local function readonly(view, method, ...)
	local ok, err = pcall(view[method], view, ...)
	return not ok and err:find(READONLY, 1, true) ~= nil
end

-- the payload lies past the linear head, so a read of it, one across the head's end and the whole
-- packet are copies; the checksum is held to a flat buffer's over the same bytes
local function read(skb)
	local view = skb:data()
	local len = #view
	local last, packet = view:getbyte(len - 1), view:getstring(0)
	local at = len - PAYLOAD - HALF
	local across, wide = view:getuint32(at), view:getint64(at - HALF)
	local past = not pcall(view.getbyte, view, len)
	report("data", len == #skb and last == FILL and across == string.unpack("=I4", packet, at + 1) and
		wide == string.unpack("=i8", packet, at - HALF + 1) and past,
		"skb %d, view %d, last byte %d, %#x and %#x across the payload's start, past it %s", #skb, len, last, across,
		wide, past and "raises" or "reads")
	local payload, same = packet:sub(-PAYLOAD) == string.char(FILL):rep(PAYLOAD), tostring(view) == packet
	report("string", #packet == len and payload and same, "%d bytes of %d, the payload read %s, tostring the same %s",
		#packet, len, payload, same)
	local flat = data.new(len, "single")
	flat:setstring(0, packet)
	local sum, expected = view:checksum(), flat:checksum()
	report("checksum", sum == expected, "%#x, a flat copy gives %#x", sum, expected)
	local net, mac = skb:data("net"), skb:data("mac")
	report("layers", #net == len - ETHER and net:getbyte(#net - 1) == FILL and #mac == len,
		"net %d, mac %d, view %d", #net, #mac, len)
	local byte, str, size = readonly(view, "setbyte", 0, view:getbyte(0)), readonly(view, "setstring", 0, ""),
		readonly(view, "resize", len)
	report("readonly", byte and str and size, "read only: setbyte %s, setstring %s, resize %s", byte, str, size)
	kept = view
end

local function unpulled(skb)
	read(skb)
	refuses(skb, "copy")
	refuses(skb, "resize", #skb - DELTA)
end

local function pulled(skb)
	local ok, err = pcall(kept.getbyte, kept, 0)
	report("cleared", #kept == 0 and not ok and err:find(BOUNDS, 1, true), "%d bytes, %s", #kept, ok and "read" or err)
	local linear = skb:data()
	ok, err = pcall(linear.setbyte, linear, 0, linear:getbyte(0))
	report("writable", ok, "%s", err)
	local len = #skb
	local view, copy = #skb:data(), #skb:copy()
	skb:resize(len - DELTA)
	local resized = #skb:data()
	report("pulled", view == len and copy == len and resized == len - DELTA, "skb %d, view %d, copy %d, resized view %d",
		len, view, copy, resized)
	done = true
	return action.SHOT -- the resized segment is not sent; TCP sends it again
end

local function test_nonlinear(ctx)
	local skb = ctx:skb()
	if done or skb:priority() ~= PRIORITY or #skb < PAYLOAD then
		return
	end
	if ctx:argument():getuint32(0) == 0 then
		unpulled(skb)
	else
		return pulled(skb)
	end
end

tc.attach(test_nonlinear)

