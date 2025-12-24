--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik = require("lunatik")
local runner  = require("lunatik.runner")
local linux   = require("linux")
local device  = require("device")
local rcu     = require("rcu")

local function nop() end -- do nothing

local s = linux.stat
local driver = {name = "systrack", open = nop, release = nop, mode = s.IRUGO}

local systrack = rcu.table()
lunatik._ENV.systrack = systrack

local toggle = true
function driver:read()
	local log = ""
	if toggle then
		rcu.map(systrack, function (symbol, counter)
			log = log .. string.format("%s: %d\n", symbol, counter:getnumber(0))
		end)
	end
	toggle = not toggle
	return log
end

runner.run("examples/systrack/probes", false)
device.new(driver)

