--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- The writer of tests/rcu/string_grace.sh: replaces the reader's key with a new, numbered string each time.

local grace = require("tests.rcu.grace")

local PERIOD <const> = 5000

local function new(n)
	local len = n % PERIOD
	return n .. ":" .. len .. ":" .. string.rep(".", len)
end

return function()
	grace.write(new)
end

