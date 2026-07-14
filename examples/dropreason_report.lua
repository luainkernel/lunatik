-- Formats the dropreason counts (see examples/dropreason.lua) as lines sorted
-- by count, one reason per line. Query it live from the REPL:
--   > return require("examples.dropreason_report")(lunatik._ENV.dropreason)

local rcu = require("rcu")

local function report(drops)
	local lines = {}
	rcu.map(drops, function(reason, count)
		table.insert(lines, string.format("%7d  %s", count, reason))
	end)
	table.sort(lines)
	return table.concat(lines, "\n")
end

return report

