--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp verdict test (see test_xdp.sh).

local xdp    = require("xdp")
local action = require("linux.xdp")

local function test_pass(ctx)
	if not ctx then
		print("xdp pass test fail: ctx is nil")
		return
	end

	local packet = ctx:packet()
	if not packet then
		print("xdp pass test fail: ctx:packet() is nil")
		return
	end

	local argument = ctx:argument()
	if not argument then
		print("xdp pass test fail: ctx:argument() is nil")
		return
	end

	print("xdp pass test pass: ctx, packet and argument are valid")
	ctx:action(action.PASS)
end

xdp.attach(test_pass)

