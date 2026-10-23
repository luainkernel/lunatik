--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- The reader of tests/rcu/object_grace.sh: reads one key, by index and through foreach, while the writer replaces it.

local rcu   = require("rcu")
local grace = require("tests.rcu.grace")

local WRITER <const> = "tests/rcu/object_grace_writer"

local function touch(_, d)
	d:getint64(0)
end

local function read(shared, key)
	local d = shared[key]
	rcu.foreach(shared, touch)
	return d ~= nil and d:getint64(0) or nil
end

return function()
	grace.read("object_grace", WRITER, read)
end

