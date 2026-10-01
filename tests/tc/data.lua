--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc data test (see test_tc.sh).

local tc     = require("tc")
local action = require("linux.tc").action
local packet = require("tests.tc.packet")

local ETH_HLEN <const> = 14 -- the Ethernet header the classifier's frame starts with
local IPV4     <const> = 4 -- the version in the high nibble of an IPv4 header's first byte

local function test_data(ctx)
	local skb = ctx:skb()
	local data = skb:data()
	if packet.isping(data) then
		local net, mac = skb:data("net"), skb:data("mac")
		local frame, datalen, netlen, maclen = #skb, #data, #net, #mac
		local version = net:getuint8(0) >> 4
		local copy = skb:copy()
		copy:resize(ETH_HLEN - 1) -- ends inside the Ethernet header, before the network header starts
		local short = copy:data("net")
		if datalen == frame and maclen == frame and netlen == frame - ETH_HLEN and version == IPV4 and
			data ~= net and data ~= mac and short == nil then
			print("tc data test pass: " ..
				"\"net\" starts at the IP header, and the views end at the frame's tail")
		else
			print(string.format("tc data test fail: frame %d, view %d, net view %d, mac view %d, " ..
				"net version %d, data() is the net view %s, the mac view %s, " ..
				"a short copy's net view %s",
				frame, datalen, netlen, maclen, version, data == net, data == mac, short ~= nil))
		end
	end
	return action.OK
end

tc.attach(test_data)

