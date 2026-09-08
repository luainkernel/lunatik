--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Atomic-context body for the newobject_oom test (see newobject_oom.sh).

local rcu = require("rcu")

local HUGE_BUCKETS <const> = 1 << 23 -- 64 MiB of buckets, past what a GFP_ATOMIC kmalloc serves

local function fail()
	local ok, err = pcall(rcu.table, HUGE_BUCKETS)
	assert(not ok, "the atomic allocation should have failed")
	assert(err:match("not enough memory"), "rcu.table raised something else: " .. err)

	local t = rcu.table(16)
	t["n"] = 42
	assert(t["n"] == 42, "table broken after failed allocation")
end

return fail

