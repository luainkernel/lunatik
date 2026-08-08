--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the rcu.map class check test (see run.sh).

local rcu  = require("rcu")
local data = require("data")
local test = require("util").test

test("rcu.map refuses an object of another class", function()
	local ok, err = pcall(rcu.map, data.new(8), function() end)
	assert(not ok, "rcu.map accepted a data object")
	assert(err:match("rcu table expected"), "unexpected error: " .. tostring(err))
end)

