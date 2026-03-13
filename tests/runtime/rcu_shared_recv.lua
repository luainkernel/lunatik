--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the rcu_shared regression test (see rcu_shared.sh).

local lunatik = require("lunatik")

local function recv()
	local t = lunatik._ENV["rcu_shared_test"]
	assert(t ~= nil, "rcu_shared_test not found in _ENV")
	assert(t["answer"] == 42, "unexpected value in shared rcu table")
end

return recv

