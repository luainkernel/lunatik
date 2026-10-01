--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict test (see test_tc.sh).

local tc      = require("tc")
local action  = require("linux.tc").action
local packet  = require("tests.tc.packet")

local MAGIC <const> = 0x4C554E41 -- matches tc_pass.bpf.c

local function test_pass(ctx)
	local skb = ctx:skb()
	if packet.isping(skb:data()) then
		skb:priority(0x1234)
		skb:mark(0xabcd)
		if skb:priority() ~= 0x1234 or skb:mark() ~= 0xabcd then
			print("tc pass test fail: priority or mark mismatch")
		elseif ctx:argument():getuint32(0) == MAGIC then
			print("tc pass test pass: packet and argument content verified")
		else
			print("tc pass test fail: argument does not carry the magic")
		end
	end
	return action.OK
end

tc.attach(test_pass)

