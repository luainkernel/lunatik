--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc shared case (see test_tc.sh).

local tc     = require("tc")
local action = require("linux.tc").action
local packet = require("tests.tc.packet")

local READONLY <const> = "read only"
local REFUSAL  <const> = "skb is not writable"

local done = false

local function refuses(cell, refusal, method, ...)
	local ok, err = pcall(method, ...)
	local refused = not ok and err:find(refusal, 1, true)
	print("tc shared: " .. cell .. (refused and " ok" or " FAIL " .. (ok and "no refusal" or err)))
end

-- each call writes, if at all, the bytes the frame already holds
local function test_shared(ctx)
	local skb = ctx:skb()
	local data = skb:data()
	if done or not packet.isecho(data) then
		return action.OK
	end
	done = true
	refuses("data", READONLY, data.setuint8, data, 0, data:getuint8(0))
	refuses("resize", REFUSAL, skb.resize, skb, #skb)
	refuses("checksum", REFUSAL, skb.checksum, skb)
	return action.OK
end

tc.attach(test_shared)

