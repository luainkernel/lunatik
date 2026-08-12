--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict test (see test_tc.sh).

local tc      = require("tc")
local action  = require("linux.tc")
local skbattr = require("skb.attr")

local ETH_HI   <const> = 12 -- ethertype, then IPv4 protocol
local ETH_LO   <const> = 13
local IPPROTO  <const> = 23
local ICMP     <const> = 1

local function test_pass(ctx)
	local skb = skbattr(ctx:skb())
	local data = skb:data()
	skb.priority = 0x1234 -- exercise the get/set attribute accessors
	skb.mark = 0xabcd
	if data:getuint8(ETH_HI) == 0x08 and data:getuint8(ETH_LO) == 0x00
			and data:getuint8(IPPROTO) == ICMP
			and skb.priority == 0x1234 and skb.mark == 0xabcd then
		print("tc pass test pass: packet content verified")
	else
		print("tc pass test fail: packet content mismatch")
	end
	ctx:action(action.ACT_OK)
end

tc.attach(test_pass)

