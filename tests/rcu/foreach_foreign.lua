--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the rcu.foreach class check test (see run.sh).

local rcu  = require("rcu")
local data = require("data")
local test = require("util").test

test("rcu.foreach refuses an object of another class", function()
	local ok, err = pcall(rcu.foreach, data.new(8), function() end)
	assert(not ok, "rcu.foreach accepted a data object")
	assert(err:match("rcu.table expected"), "unexpected error: " .. tostring(err))
end)

