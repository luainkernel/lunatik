--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe dropreason test (see dropreason.sh).
-- examples/dropreason/monitor.lua picks its target the same way.

local probe      = require("probe")
local linux      = require("linux")
local dropreason = require("linux.dropreason")

local BATCH <const> = 16 -- the datagrams dropreason.sh sends

-- the drop path, newest name first: v6.11 turned kfree_skb_reason(skb, reason)
-- into a static inline over sk_skb_reason_drop(sk, skb, reason)
local targets = {
	{symbol = "sk_skb_reason_drop", reason = 2},
	{symbol = "kfree_skb_reason", reason = 1},
}

local function find()
	local tried = {}
	for _, target in ipairs(targets) do
		if linux.lookup(target.symbol) then
			return target.symbol, target.reason
		end
		table.insert(tried, target.symbol)
	end
	error("couldn't find " .. table.concat(tried, " or "))
end

local SYMBOL <const>, REASON <const> = find()
local NO_SOCKET <const> = dropreason.NO_SOCKET

local dropped = 0

local function pre(_, _, argument)
	if dropped >= BATCH or argument(REASON) ~= NO_SOCKET then
		return
	end

	dropped = dropped + 1
	if dropped == BATCH then
		print("probe dropreason: reason")
	end
end

print("probe dropreason: symbol " .. SYMBOL)
probe.new(SYMBOL, {pre = pre})

