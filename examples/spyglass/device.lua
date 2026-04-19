--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local device = require("device")
local stat   = require("linux.stat")
local fifo   = require("fifo")
local runner = require("lunatik.runner")

local BUFSIZE <const> = 4096

local script = "examples/spyglass/notifier"
local driver = {name = "spyglass", mode = stat.IRUGO}
local log    = fifo.new(BUFSIZE)

function driver:read()
	local data = log:pop(BUFSIZE)
	return data
end

device.new(driver)

local notifier = runner.run(script, "hardirq")
notifier:resume(log)

driver.sentinel = setmetatable({}, {__gc = function()
	runner.stop(script)
end})

