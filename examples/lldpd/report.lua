--
-- SPDX-FileCopyrightText: (c) 2025-2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Query API for the lldpd example (examples/lldpd.lua). Bind it in the REPL:
--   > n = require("examples.lldpd.report")
--   > n.report()
--   > n["chassis@port"]

local rcu     = require("rcu")
local lunatik = require("lunatik")

local neighbors = {}

local function track()
	return lunatik._ENV.lldpd or error("examples/lldpd is not running")
end

function neighbors.report()
	local lines = {}
	rcu.map(track(), function(key, remaining)
		table.insert(lines, string.format("%s  %d", key, remaining))
	end)
	table.sort(lines)
	return table.concat(lines, "\n")
end

local remaining = {}

function remaining.__index(_, key)
	return track()[key]
end

return setmetatable(neighbors, remaining)

