--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the newobject_oom test (see newobject_oom.sh).

local rcu = require("rcu")
local test = require("util").test

local HUGE_BUCKETS <const> = 1 << 58

test("rcu.table with huge size fails gracefully", function()
	assert(not pcall(rcu.table, HUGE_BUCKETS), "huge allocation should have failed")
	collectgarbage() -- force the failed object's finalizer to run now
end)

test("runtime usable after failed allocation", function()
	local t = rcu.table(16)
	t["n"] = 42
	assert(t["n"] == 42, "table broken after failed allocation")
end)

