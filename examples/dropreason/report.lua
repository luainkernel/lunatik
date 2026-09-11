--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Query API for the dropreason monitor (examples/dropreason/monitor.lua). Bind it
-- in the REPL, read a count by reason name, or call report() for the full picture:
--   > drops = require("examples.dropreason.report")
--   > drops.NO_SOCKET
--   1
--   > drops.report()

local rcu     = require("rcu")
local lunatik = require("lunatik")

local drops = {}

local function track()
	return lunatik._ENV.dropreason or error("the dropreason monitor is not running")
end

-- Every drop count, one reason per line, sorted by count.
function drops.report()
	local lines = {}
	rcu.map(track(), function(reason, count)
		table.insert(lines, string.format("%7d  %s", count, reason))
	end)
	table.sort(lines)
	return table.concat(lines, "\n")
end

local function count(_, reason)
	return track()[reason]
end

return setmetatable(drops, {__index = count})

