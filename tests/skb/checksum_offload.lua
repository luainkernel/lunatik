--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the checksum_offload test (see checksum_offload.sh).

local filter = require("tests.skb.filter")
local nf     = require("linux.nf")
local linux  = require("linux")

local format = string.format

local IFACE   <const> = "lunatikckd1" -- DST_PEER in checksum_offload.sh
local PAYLOAD <const> = 400  -- PAYLOAD in checksum_offload.sh
local REPORT  <const> = 151  -- REPORT in checksum_offload.sh
local MTU     <const> = 1500

local ifindex = linux.ifindex(IFACE)
local seen, gso = 0, 0

local function offload_hook(skb)
	local len = #skb
	if skb:ifindex() ~= ifindex then
		return nf.action.ACCEPT
	elseif len == REPORT then
		print(format("skb checksum offload: seen %d gso %d", seen, gso))
		seen, gso = 0, 0
	elseif len >= PAYLOAD then
		skb:checksum()
		seen = seen + 1
		if len > MTU then
			gso = gso + 1
		end
	end
	return nf.action.ACCEPT
end

filter.register(offload_hook, nf.proto.INET, nf.inet.POST_ROUTING)

