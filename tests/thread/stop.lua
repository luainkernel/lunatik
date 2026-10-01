--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread stop test (see stop.sh).

local lunatik = require("lunatik")
local thread  = require("thread")

local EXIT   <const> = "tests/thread/exit"
local NAME   <const> = "lunatik_stop"
local PREFIX <const> = "thread stop test: "

local function start(body)
	return thread.run(lunatik.runtime(body), NAME)
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
	print(PREFIX .. "closed")
end

local function driver()
	closed()
end

return driver

