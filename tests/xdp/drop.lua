--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp verdict test (see test_xdp.sh).

local xdp    = require("xdp")
local action = require("linux.xdp")

local function test_drop(ctx)
	print("xdp drop test pass: verdict set to drop")
	ctx:action(action.DROP)
end

xdp.attach(test_drop)

