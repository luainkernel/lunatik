--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Answers "why is my packet dying?". A kprobe on the out-of-line drop path, where
-- every kfree_skb() lands, reads the reason off the probed function's arguments and
-- counts the drops by name in an RCU table published on the shared environment,
-- where any runtime, the REPL included, reads it live. A drop freed from hardirq
-- (dev_kfree_skb_any()) or as a segment list (kfree_skb_list()) never reaches it
-- and is not counted. tests/probe/dropreason.lua probes the same pair.
--
-- Usage:
--   sudo lunatik run examples/dropreason/monitor hardirq
--   echo x > /dev/udp/127.0.0.1/9999              # trigger a NO_SOCKET drop
--   sudo lunatik                                  # opens the kernel REPL
--   > drops = require("examples.dropreason.report")
--   > drops.NO_SOCKET
--   1
--   > drops.report()

local probe      = require("probe")
local rcu        = require("rcu")
local linux      = require("linux")
local dropreason = require("linux.dropreason")
local env        = require("lunatik")._ENV

-- the first drop for this reason has its registers and call trace dumped to
-- dmesg, which is what names the drop site; any name in linux.dropreason does
local WATCH <const> = "NO_SOCKET"

local targets = {
	-- v6.11 and later: sk_skb_reason_drop(sk, skb, reason)
	{symbol = "sk_skb_reason_drop", reason = 2},
	-- v6.10 and earlier: kfree_skb_reason(skb, reason)
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
local CONSUMED <const> = dropreason.CONSUMED -- freed, not dropped

local names = {}
for name, reason in pairs(dropreason) do
	names[reason] = name
end

local track = rcu.table()
env.dropreason = track

local caught = false

local function pre(_, dump, argument)
	local reason = argument(REASON)
	if reason == CONSUMED then
		return
	end

	local name = names[reason] or "UNKNOWN"
	track[name] = (track[name] or 0) + 1

	if name == WATCH and not caught then
		caught = true
		print("dropreason: caught " .. WATCH)
		dump()
	end
end

local function unpublish()
	env.dropreason = nil
end

print("dropreason: probing " .. SYMBOL)
probe.new(SYMBOL, {pre = pre, sentinel = setmetatable({}, {__gc = unpublish})})

