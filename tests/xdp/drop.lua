--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local xdp    = require("xdp")
local action = require("linux.xdp")

local function test_drop(ctx)
	if not ctx then
		print("xdp drop test fail: ctx is nil")
		return
	end
	print("xdp drop test pass: verdict set to drop")
	ctx:action(action.DROP)
end

xdp.attach(test_drop)

