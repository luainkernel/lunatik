--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict test (see test_tc.sh).

local tc      = require("tc")
local action  = require("linux.tc")
local skbattr = require("skb.attr")

local MAGIC    <const> = 0x4C554E41 -- matches tc_pass.bpf.c
local ETH_HI   <const> = 12 -- ethertype, then IPv4 protocol
local ETH_LO   <const> = 13
local IPPROTO  <const> = 23
local ICMP     <const> = 1

local function test_pass(ctx)
	local raw  = ctx:skb()
	local skb  = skbattr.new(raw)
	local data = raw:data()
	skb.priority = 0x1234 -- exercise the attribute accessors
	skb.mark = 0xabcd
	if data:getuint8(ETH_HI) == 0x08 and data:getuint8(ETH_LO) == 0x00
			and data:getuint8(IPPROTO) == ICMP
			and skb.priority == 0x1234 and skb.mark == 0xabcd then
		if ctx:argument():getuint32(0) == MAGIC then
			print("tc pass test pass: packet and argument content verified")
		else
			print("tc pass test fail: argument does not carry the magic")
		end
	else
		print("tc pass test fail: packet content mismatch")
	end
	ctx:action(action.ACT_OK)
end

tc.attach(test_pass)

