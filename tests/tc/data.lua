--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc data test (see test_tc.sh).

local tc     = require("tc")
local action = require("linux.tc").action
local packet = require("tests.tc.packet")

local function test_data(ctx)
	local skb = ctx:skb()
	if packet.isping(skb:data()) then
		local frame, net, mac = #skb, #skb:data(), #skb:data("mac")
		if net == frame and mac == frame then
			print("tc data test pass: the net and mac views end at the frame's tail")
		else
			print(string.format("tc data test fail: frame %d, net view %d, mac view %d", frame, net, mac))
		end
	end
	return action.OK
end

tc.attach(test_data)

