--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc resend case (see test_tc.sh).

local tc     = require("tc")
local action = require("linux.tc").action
local packet = require("tests.tc.packet")

local ICMPTYPE <const> = 34 -- ICMPTYPE in packet.lua
local FLIP     <const> = 0xff -- the bits the write after forward() changes

local function test_resend(ctx)
	local skb = ctx:skb()
	local data = skb:data()
	if not packet.isping(data) then
		return action.OK
	end
	skb:forward()
	data:setuint8(ICMPTYPE, data:getuint8(ICMPTYPE) ~ FLIP)
	print("tc resend test pass")
	return action.SHOT
end

tc.attach(test_resend)

