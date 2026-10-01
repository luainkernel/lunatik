--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc non-linear test (see test_tc.sh).

local tc     = require("tc")
local action = require("linux.tc")

local PRIORITY <const> = 0x13690000 -- PRIORITY in test_tc.sh
local PAYLOAD  <const> = 1024 -- PAYLOAD in test_tc.sh
local DELTA    <const> = 16
local REFUSAL  <const> = "skb is not linear"

local done = false

local function report(cell, ok, format, ...)
	print("tc nonlinear: " .. cell .. (ok and " ok" or " FAIL " .. string.format(format, ...)))
end

local function refuses(skb, method, ...)
	local ok, err = pcall(skb[method], skb, ...)
	report(method, not ok and err:find(REFUSAL, 1, true), "%s", ok and "no refusal" or err)
end

local function unpulled(skb)
	refuses(skb, "data")
	refuses(skb, "copy")
	refuses(skb, "resize", #skb - DELTA)
end

local function pulled(skb)
	local len = #skb
	local view, copy = #skb:data(), #skb:copy()
	skb:resize(len - DELTA)
	local resized = #skb:data()
	report("pulled", view == len and copy == len and resized == len - DELTA, "skb %d, view %d, copy %d, resized view %d",
		len, view, copy, resized)
	done = true
	return action.ACT_SHOT -- the resized segment is not sent; TCP sends it again
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

