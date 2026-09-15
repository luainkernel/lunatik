--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the partitioned classifier test (see partition.sh).

local tc      = require("tc")
local action  = require("linux.tc")
local rcu     = require("rcu")
local skbattr = require("skb.attr")

local CALLS   <const> = "calls"
local BUCKETS <const> = 1

local counts = rcu.table(BUCKETS)

-- the count says how many packets of a run reached Lua, which is the whole point of the
-- partition: the second packet of a flow is decided from the map and never gets here
local function test_partition(ctx)
	local n = (counts[CALLS] or 0) + 1
	counts[CALLS] = n
	local skb = skbattr.new(ctx:skb())
	skb.priority = ctx:argument():getint64(0)
	print("luaebpf partition test call " .. n .. ": priority " .. skb.priority)
	ctx:action(action.ACT_OK)
end

tc.attach(test_partition)

