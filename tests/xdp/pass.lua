--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp verdict test (see test_xdp.sh).

local xdp    = require("xdp")
local action = require("linux.xdp").action
local packet = require("tests.xdp.packet")

local MAGIC <const> = 0x4C554E41 -- matches xdp_pass.bpf.c

local function test_pass(ctx)
	if packet.isping(ctx:packet()) then
		local arg = ctx:argument()
		if arg:getuint32(0) ~= MAGIC then
			print("xdp pass test fail: argument does not carry the magic")
		elseif ctx:ingress() ~= arg:getuint32(4) then
			print("xdp pass test fail: ingress differs from the program's")
		elseif ctx:queue() ~= arg:getuint32(8) then
			print("xdp pass test fail: queue differs from the program's")
		else
			print("xdp pass test pass: packet, argument and receive queue verified")
		end
	end
	return action.PASS
end

xdp.attach(test_pass)

