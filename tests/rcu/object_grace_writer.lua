--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- The writer of tests/rcu/object_grace.sh: replaces the reader's key with a new, numbered object each time.

local lunatik = require("lunatik")
local data    = require("data")
local thread  = require("thread")
local linux   = require("linux")

local KEY <const> = "slot"
local RUN_MS <const> = 10000
local SIZE <const> = 8

local function milliseconds()
	return linux.time() // 1000000
end

return function()
	local grace = lunatik._ENV.grace
	local deadline = milliseconds() + RUN_MS
	local n = 0
	while not thread.shouldstop() and milliseconds() < deadline do
		n = n + 1
		local d = data.new(SIZE)
		d:setnumber(0, n)
		grace[KEY] = d
	end
	grace[KEY] = nil
end

