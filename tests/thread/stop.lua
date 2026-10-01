--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread stop test (see stop.sh).

local lunatik    = require("lunatik")
local thread     = require("thread")
local completion = require("completion")
local rcu        = require("rcu")

local EXIT      <const> = "tests/thread/exit"
local RAISE     <const> = "tests/thread/stop_raise"
local FINALIZED <const> = "tests/thread/stop_finalized"
local NAME      <const> = "lunatik_stop"
local PREFIX    <const> = "thread stop test: "
local TIMEOUT   <const> = 3000
local THREAD    <const> = "thread"
local STOPPED   <const> = "stopped"

local function start(body, ...)
	return thread.run(lunatik.runtime(body), NAME, ...)
end

local function scope(t)
	local held <close> = t
end

local function closed()
	local t = start(EXIT)
	local class = getmetatable(t)
	assert(class.__close == class.stop, "a thread's __close is not its stop")

	scope(t)
	local task = t:task()
	local ok, err = pcall(task.pid, task)
	assert(not ok and tostring(err):match("closed object"), "a to-be-closed thread was not stopped")
	t:stop()
end

local function returned()
	local t = start(EXIT)
	assert(t:stop() == true, "the stop of a thread whose body did not raise did not return true")
	assert(t:stop() == true, "the stop of a thread already stopped did not return true")
end

local function raised()
	local running = completion.new()
	local t = start(RAISE, running)
	assert(running:wait(TIMEOUT), "the body that raises did not run")
	assert(t:stop() == false, "the stop of a thread whose body raised did not return false")
end

local function finalized()
	local shared, running = rcu.table(1), completion.new()
	local t = start(FINALIZED, shared, running)
	shared[THREAD] = t
	local ran = running:wait(TIMEOUT)
	collectgarbage() -- the runtime's handle, so the stop drops its last reference
	local ok, stopped = pcall(t.stop, t)
	shared[THREAD] = nil -- a stop that raised leaves the thread, its runtime and the table holding each other
	assert(ran, "the body that leaves the sentinel did not run")
	assert(ok and stopped, "the stop that closes the thread's runtime did not return true")
	assert(shared[STOPPED] == true, "the stop from a finalizer of the thread's runtime did not return true")
end

-- a failed case reports its error and the next one runs
local function check(name, case)
	local ok, err = pcall(case)
	print(ok and PREFIX .. name or err)
end

local function driver()
	check("closed", closed)
	check("returned", returned)
	check("raised", raised)
	check("finalized", finalized)
end

return driver

