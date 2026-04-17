--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only

local device = require("device")
local linux  = require("linux")
local rcu    = require("rcu")
local runner = require("lunatik.runner")

local s = require("linux.stat")
local driver = {name = "systrack", mode = s.IRUGO}

local track = rcu.table()

local toggle = true
function driver:read()
	if not toggle then
		toggle = true
		return ""
	end
	toggle = false
	local log = {}
	rcu.map(track, function(symbol, count)
		table.insert(log, symbol .. ": " .. tostring(count))
	end)
	table.sort(log)
	return table.concat(log, "\n") .. "\n"
end

device.new(driver)

local probe = runner.run("examples/systrack/probe", "hardirq")
probe:resume(track)

driver.sentinel = setmetatable({}, {__gc = function()
	runner.stop("examples/systrack/probe")
end})

