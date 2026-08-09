--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp verdict test (see test_xdp.sh).

local xdp    = require("xdp")
local action = require("linux.xdp")

local MAGIC    <const> = 0x4C554E41 -- matches xdp_pass.bpf.c
local ETH_HI   <const> = 12 -- ethertype, then IPv4 protocol
local ETH_LO   <const> = 13
local IPPROTO  <const> = 23
local ICMP     <const> = 1

local function test_pass(ctx)
	local packet = ctx:packet()
	if packet:getuint8(ETH_HI) == 0x08 and packet:getuint8(ETH_LO) == 0x00
			and packet:getuint8(IPPROTO) == ICMP then
		if ctx:argument():getuint32(0) == MAGIC then
			print("xdp pass test pass: packet and argument content verified")
		else
			print("xdp pass test fail: argument does not carry the magic")
		end
	end
	ctx:action(action.PASS)
end

xdp.attach(test_pass)

