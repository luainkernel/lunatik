--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict test (see test_tc.sh).

local tc    = require("tc")
local action = require("linux.tc").action

local function test_drop()
	print("tc drop test pass: verdict set to drop")
	return action.SHOT
end

tc.attach(test_drop)

