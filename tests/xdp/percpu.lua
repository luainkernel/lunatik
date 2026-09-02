--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp percpu dispatch test (see test_xdp.sh).

local lunatik = require("lunatik")
local xdp     = require("xdp")
local action  = require("linux.xdp")

local ETH_HI  <const> = 12 -- ethertype, then IPv4 protocol
local ETH_LO  <const> = 13
local IPPROTO <const> = 23
local ICMP    <const> = 1

local cpu = lunatik.cpu()

local function test_percpu(ctx)
	local packet = ctx:packet()
	-- the namespace also emits IPv6 autoconf traffic, from a context the test does not pin
	if packet:getuint8(ETH_HI) == 0x08 and packet:getuint8(ETH_LO) == 0x00
			and packet:getuint8(IPPROTO) == ICMP then
		print("xdp percpu test hit: cpu " .. cpu)
	end
	ctx:action(action.PASS)
end

xdp.attach(test_percpu)

