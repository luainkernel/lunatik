--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Child script for the closing test (see closing.sh).

local env = require("lunatik")._ENV

local OPENED <const> = "tests/runtime/closing.opened"
local CLOSED <const> = "tests/runtime/closing.closed"

local function count(key)
	env[key] = env[key] + 1
end

local function echo(object)
	while true do
		object = coroutine.yield(object)
	end
end

count(OPENED)
sentinel = setmetatable({}, {__gc = function() count(CLOSED) end})

return echo

