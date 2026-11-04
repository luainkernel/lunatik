--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the monitor collector test (see collector.sh).

local data = require("data")
local fifo = require("fifo")
local test = require("tests.lib").test

local CAPACITY <const> = 16
local SIZE <const> = 1024
local CALLS <const> = 4096
local BOUND <const> = CALLS * SIZE // 4
local CYCLES <const> = 8

local queue = fifo.new(CAPACITY)
local buffer = data.new(SIZE)

test("a monitored method that returns leaves a stopped collector stopped", function()
	collectgarbage("stop")
	queue:push("x")
	assert(not collectgarbage("isrunning"), "fifo:push restarted the collector")
end)

test("a monitored method that raises leaves a stopped collector stopped", function()
	collectgarbage("stop")
	assert(not pcall(queue.pop, queue, CAPACITY + 1), "fifo:pop took a size past the capacity")
	assert(not collectgarbage("isrunning"), "fifo:pop restarted the collector as it raised")
end)

test("a monitored method that returns leaves a running collector running", function()
	collectgarbage("restart")
	queue:pop(1)
	assert(collectgarbage("isrunning"), "fifo:pop left the collector stopped")
end)

test("a monitored method that raises leaves a running collector running", function()
	collectgarbage("restart")
	assert(not pcall(queue.pop, queue, CAPACITY + 1), "fifo:pop took a size past the capacity")
	assert(collectgarbage("isrunning"), "fifo:pop left the collector stopped as it raised")
end)

test("a loop of monitored methods that allocate collects as it runs", function()
	collectgarbage("restart")
	collectgarbage("collect")
	local before = collectgarbage("count")
	for _ = 1, CALLS do
		buffer:getstring(0)
	end
	local grown = collectgarbage("count") - before
	assert(grown < BOUND, "data:getstring grew the heap by " .. grown .. " bytes")
end)

test("a loop of monitored methods that allocate leaves a stopped collector stopped", function()
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, CALLS do
		buffer:getstring(0)
	end
	local grown = collectgarbage("count") - before
	assert(not collectgarbage("isrunning"), "data:getstring restarted the collector")
	assert(grown >= CALLS * SIZE, "data:getstring stepped a stopped collector: the heap grew by " .. grown .. " bytes")
end)

test("a loop of monitored methods that allocate nothing takes no collector step", function()
	collectgarbage("restart")
	local cycles = 0
	local armed = true
	local arm
	local function finalize()
		cycles = cycles + 1
		if armed then
			arm()
		end
	end
	function arm()
		setmetatable({}, {__gc = finalize})
	end
	collectgarbage("collect")
	arm()
	for _ = 1, CALLS do
		buffer:getbyte(0)
	end
	armed = false
	assert(cycles < CYCLES, "data:getbyte stepped the collector through " .. cycles .. " cycles")
end)

