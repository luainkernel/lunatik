--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc checksum test (see test_tc.sh).

local tc   = require("tc")
local csum = require("tests.skb.csum")

local PRIORITY <const> = 0x17020000 -- CSUM_PRIORITY in test_tc.sh

local IP_CHECK    <const> = 10
local IP_ADDRS    <const> = 12
local IP_ADDRSLEN <const> = 8
local UDP_CHECK   <const> = 6
local UDP         <const> = 17

local function test_checksum(ctx)
	local skb = ctx:skb()
	if skb:priority() ~= PRIORITY then -- the datagram is the one packet its socket sends
		return
	end
	local net = skb:data("net")
	local hlen = (net:getuint8(0) & 0x0f) * 4
	net:setuint16(IP_CHECK, 0)
	net:setuint16(hlen + UDP_CHECK, 0)
	skb:checksum()
	local ip, udp = net:checksum(0, hlen) == 0, csum.summed(net, IP_ADDRS, IP_ADDRSLEN, hlen, UDP)
	print("tc checksum: summed" .. (ip and udp and " ok" or string.format(" FAIL ip %s, udp %s", ip, udp)))
end

tc.attach(test_checksum)

