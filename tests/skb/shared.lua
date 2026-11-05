--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side hooks for the shared test (see shared.sh).

local filter = require("tests.skb.filter")
local nf     = require("linux.nf")

local FLIP         <const> = 0xff -- FLIP in shared_tap.lua
local WRITTEN_MARK <const> = 1301 -- WRITTEN_MARK in shared_tap.lua
local SUMMED_MARK  <const> = 1302 -- SUMMED_MARK in shared_tap.lua

local function written(skb)
	local packet = skb:data("net")
	local last = #packet - 1
	packet:setuint8(last, packet:getuint8(last) ~ FLIP)
	return nf.action.ACCEPT
end

local function summed(skb)
	skb:checksum()
	print("skb shared: summed hooked")
	return nf.action.ACCEPT
end

filter.register(written, nf.proto.INET, nf.inet.PRE_ROUTING, WRITTEN_MARK)
filter.register(summed, nf.proto.INET, nf.inet.PRE_ROUTING, SUMMED_MARK)

