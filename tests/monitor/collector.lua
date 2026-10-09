--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the monitor collector test (see collector.sh).

local fifo = require("fifo")
local test = require("tests.lib").test

local CAPACITY <const> = 16

local queue = fifo.new(CAPACITY)

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

