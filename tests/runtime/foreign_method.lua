--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the method class check test (see foreign_method.sh).

local device   = require("device")
local notifier = require("notifier")
local rcu      = require("rcu")
local data     = require("data")
local stat     = require("linux.stat")
local test     = require("util").test

local foreign = data.new(8)

local function refused(name, method, ...)
	local ok, err = pcall(method, foreign, ...)
	assert(not ok, name .. " accepted a data object")
	assert(err:match("expected"), name .. " raised something else: " .. err)
end

local function nop() end

test("device:stop refuses an object of another class", function()
	local driver = {name = "foreign_method", mode = stat.IRUGO, read = function() return "" end}
	local dev = device.new(driver)
	refused("device:stop", getmetatable(dev).stop)
	dev:stop()
end)

test("notifier:stop refuses an object of another class", function()
	local n = notifier.netdevice(nop)
	refused("notifier:stop", getmetatable(n).stop)
	n:stop()
end)

test("rcu.table index and newindex refuse an object of another class", function()
	local t = rcu.table()
	refused("rcu.table.__index", getmetatable(t).__index, "key")
	refused("rcu.table.__newindex", getmetatable(t).__newindex, "key", 1)
end)

