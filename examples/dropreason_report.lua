-- Query API for the dropreason monitor (examples/dropreason.lua). Bind it in the
-- REPL, read a count by reason name, or call report() for the full picture:
--   > drops = require("examples.dropreason_report")
--   > drops.NO_SOCKET
--   16
--   > return drops.report()

local rcu     = require("rcu")
local lunatik = require("lunatik")

local drops = {}

-- All drop counts as lines sorted by count, one reason per line.
function drops.report()
	local lines = {}
	rcu.map(lunatik._ENV.dropreason, function(reason, count)
		table.insert(lines, string.format("%7d  %s", count, reason))
	end)
	table.sort(lines)
	return table.concat(lines, "\n")
end

return setmetatable(drops, {__index = function(_, reason)
	return lunatik._ENV.dropreason[reason]
end})

