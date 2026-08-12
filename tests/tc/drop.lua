--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict test (see test_tc.sh).

local tc    = require("tc")
local action = require("linux.tc")

local function test_drop(ctx)
	print("tc drop test pass: verdict set to drop")
	ctx:action(action.ACT_SHOT)
end

tc.attach(test_drop)

