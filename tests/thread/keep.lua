--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread keep test (see keep.sh).

local lunatik    = require("lunatik")
local thread     = require("thread")
local completion = require("completion")
local rcu        = require("rcu")
local test       = require("tests.lib").test

local EXIT    <const> = "tests/thread/exit"
local WAIT    <const> = "tests/thread/wait_body"
local CREATOR <const> = "tests/thread/creator"
local NAME    <const> = "lunatik_keep"
local TIMEOUT <const> = 3000

local weak = {__mode = "v"}

local function kept()
	local handles = setmetatable({thread.run(lunatik.runtime(EXIT), NAME)}, weak)
	collectgarbage()
	local t = handles[1]
	local stopped = t ~= nil and t:stop()
	t = nil
	collectgarbage()
	assert(stopped, "a thread whose handle was dropped was collected while the runtime that started it runs")
	assert(handles[1] == nil, "a stopped thread stayed kept by the runtime that started it")
end

-- a handle read back from a table is a second one, which the runtime does not keep
local function cloned()
	local shared, running, stopped = rcu.table(1), completion.new(), completion.new()
	local t = thread.run(lunatik.runtime(WAIT), NAME, running, stopped)
	local ran = running:wait(TIMEOUT)
	shared.handle = t
	local handles = setmetatable({shared.handle}, weak)
	shared.handle = nil
	collectgarbage()
	local seen = stopped:wait(0)
	t:stop()
	assert(ran, "the thread body did not run")
	assert(handles[1] == nil, "a second handle of a thread was not collected")
	assert(not seen, "collecting a second handle of a thread in the runtime that started it stopped it")
end

local function handover()
	local running, stopped = completion.new(), completion.new()
	local creator = lunatik.runtime(CREATOR)
	local t = creator:resume(lunatik.runtime(WAIT), running, stopped)
	return creator, t, stopped, running:wait(TIMEOUT)
end

local function ended()
	local creator, t, stopped, ran = handover()
	creator:stop()
	local seen = stopped:wait(0)
	t:stop()
	assert(ran, "the thread body did not run")
	assert(seen, "the end of the runtime that started a thread did not stop it")
end

local function foreign()
	local creator, t, stopped, ran = handover()
	local returned = t:stop()
	creator:stop()
	assert(ran, "the thread body did not run")
	assert(returned and stopped:wait(0), "a stop from another runtime did not stop the thread")
end

local function driver()
	test("kept", kept)
	test("cloned", cloned)
	test("ended", ended)
	test("foreign", foreign)
end

return driver

