--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict test (see test_tc.sh).

local tc    = require("tc")
local action = require("linux.tc")

local function drop_then_detach(ctx)
	ctx:action(action.ACT_SHOT)
	tc.detach()
	print("tc detach test pass: verdict set and callback detached")
end

tc.attach(drop_then_detach)

