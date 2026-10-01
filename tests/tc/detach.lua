--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict test (see test_tc.sh).

local tc     = require("tc")
local action = require("linux.tc")
local packet = require("tests.tc.packet")

local function drop_then_detach(ctx)
	if not packet.isping(ctx:skb():data()) then
		return action.ACT_OK
	end
	tc.detach()
	print("tc detach test pass: verdict returned and callback detached")
	return action.ACT_SHOT
end

tc.attach(drop_then_detach)

