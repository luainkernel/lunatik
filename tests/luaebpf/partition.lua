--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel script of the partition case (see partition.sh).

local tc     = require("tc")
local action = require("linux.tc").action
local rcu    = require("rcu")

local CALLS   <const> = "calls"
local BUCKETS <const> = 1

local counts = rcu.table(BUCKETS)

local function callback(ctx)
	local calls = (counts[CALLS] or 0) + 1
	counts[CALLS] = calls
	local priority = ctx:skb():priority(ctx:argument():getint64(0))
	print("luaebpf partition test call " .. calls .. ": priority " .. priority)
	return action.OK
end

tc.attach(callback)

