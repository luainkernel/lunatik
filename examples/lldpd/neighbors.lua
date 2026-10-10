--
-- SPDX-FileCopyrightText: (c) 2026 Harshdeep Singh <harshdeep.singh.292006@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Query API for the lldpd example (examples/lldpd/daemon.lua). Bind it in the REPL:
--   > neighbors = require("examples.lldpd.neighbors")
--   > neighbors.list()
--   > neighbors["chassis@port"]

local rcu     = require("rcu")
local lunatik = require("lunatik")

local function neighbors()
	return lunatik._ENV.lldpd or error("lldpd is not running")
end

local report = {}

function report.list()
	local lines = {}
	rcu.foreach(neighbors(), function(key, ttl)
		table.insert(lines, string.format("%s  %d", key, ttl))
	end)
	table.sort(lines)
	return table.concat(lines, "\n")
end

local remaining = {}

function remaining.__index(_, key)
	return neighbors()[key]
end

return setmetatable(report, remaining)

