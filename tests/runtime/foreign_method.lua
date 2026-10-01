--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the method class check test (see foreign_method.sh).

local device   = require("device")
local notifier = require("notifier")
local rcu      = require("rcu")
local stat     = require("linux.stat")
local test     = require("tests.lib").test
local check    = require("tests.runtime.check")

local function nop() end

local function empty()
	return ""
end

test("device:stop refuses an object of another class", function()
	local driver = {name = "foreign_method", mode = stat.IRUGO, read = empty}
	local dev = device.new(driver)
	check.refused("device:stop", getmetatable(dev).stop)
	dev:stop()
end)

test("notifier:stop refuses an object of another class", function()
	local n = notifier.netdevice(nop)
	check.refused("notifier:stop", getmetatable(n).stop)
	n:stop()
end)

test("rcu.table index and newindex refuse an object of another class", function()
	local t = rcu.table()
	check.refused("rcu.table.__index", getmetatable(t).__index, "key")
	check.refused("rcu.table.__newindex", getmetatable(t).__newindex, "key", 1)
end)

