--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp verdict test (see test_xdp.sh).

local xdp    = require("xdp")
local action = require("linux.xdp")
local packet = require("tests.xdp.packet")

local MAGIC <const> = 0x4C554E41 -- matches xdp_pass.bpf.c

local function test_pass(ctx)
	if packet.isping(ctx:packet()) then
		if ctx:argument():getuint32(0) == MAGIC then
			print("xdp pass test pass: packet and argument content verified")
		else
			print("xdp pass test fail: argument does not carry the magic")
		end
	end
	ctx:action(action.PASS)
end

xdp.attach(test_pass)

