--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict test (see test_tc.sh).

local tc      = require("tc")
local action  = require("linux.tc")
local skbattr = require("skb.attr")
local packet  = require("tests.tc.packet")

local MAGIC <const> = 0x4C554E41 -- matches tc_pass.bpf.c

local function test_pass(ctx)
	local raw = ctx:skb()
	if packet.isicmp(raw:data()) then
		local skb = skbattr.new(raw)
		skb.priority = 0x1234 -- exercise the attribute accessors
		skb.mark = 0xabcd
		if skb.priority ~= 0x1234 or skb.mark ~= 0xabcd then
			print("tc pass test fail: attribute mismatch")
		elseif ctx:argument():getuint32(0) == MAGIC then
			print("tc pass test pass: packet and argument content verified")
		else
			print("tc pass test fail: argument does not carry the magic")
		end
	end
	ctx:action(action.ACT_OK)
end

tc.attach(test_pass)

