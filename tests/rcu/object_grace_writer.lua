--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- The writer of tests/rcu/object_grace.sh: replaces the reader's key with a new, numbered object each time.

local data  = require("data")
local grace = require("tests.rcu.grace")

local SIZE <const> = 8

local function new(n)
	local d = data.new(SIZE)
	d:setint64(0, n)
	return d
end

return function()
	grace.write(new)
end

