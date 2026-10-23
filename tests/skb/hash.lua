--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the skb hash test (see hash.sh).

local filter    = require("tests.skb.filter")
local nf        = require("linux.nf")

local PRIORITY <const> = 0x12380000
local FLOWS    <const> = 3

local function hash_hook(skb)
	local flow = skb:priority() - PRIORITY
	if flow >= 1 and flow <= FLOWS then
		print("skb hash: " .. flow .. " " .. skb:hash())
	end
	return nf.action.ACCEPT
end

filter.register(hash_hook, nf.proto.IPV4, nf.inet.LOCAL_OUT)

