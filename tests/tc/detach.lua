--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict test (see test_tc.sh).

local tc     = require("tc")
local action = require("linux.tc").action
local packet = require("tests.tc.packet")

local held = setmetatable({}, {__mode = "v"})

local function drop_then_detach(ctx)
	if not packet.isping(ctx:skb():data()) then
		return action.OK
	end
	tc.detach()
	held.ctx = ctx
	ctx = nil
	collectgarbage()
	if held.ctx == nil then
		print("tc detach test fail: the context was collected inside its callback")
	else
		print("tc detach test pass: verdict returned and callback detached")
	end
	return action.SHOT
end

tc.attach(drop_then_detach)

