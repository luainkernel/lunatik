--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- The reader of tests/rcu/string_grace.sh: reads one key, by index and through foreach, while the writer replaces it.

local rcu   = require("rcu")
local grace = require("tests.rcu.grace")

local WRITER  <const> = "tests/rcu/string_grace_writer"
local PATTERN <const> = "^(%d+):(%d+):(%.*)$"

local function check(s)
	local n, len, dots = s:match(PATTERN)
	assert(n ~= nil and #dots == tonumber(len), "a string read was not one the writer made: " .. #s .. " bytes")
	return tonumber(n)
end

local function touch(_, s)
	check(s)
end

local function read(shared, key)
	local s = shared[key]
	rcu.foreach(shared, touch)
	return s ~= nil and check(s) or nil
end

return function()
	grace.read("string_grace", WRITER, read)
end

