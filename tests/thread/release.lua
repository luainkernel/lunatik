--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread release test (see release.sh).

local lunatik    = require("lunatik")
local thread     = require("thread")
local completion = require("completion")

local BODY    <const> = "tests/thread/release_body"
local NAME    <const> = "lunatik_release"
local PREFIX  <const> = "thread release test: "
local TIMEOUT <const> = 3000
local PAUSE   <const> = 500

local function start()
	local done, closed = completion.new(), completion.new()
	local t = thread.run(lunatik.runtime(BODY), NAME, done, closed)
	assert(done:wait(TIMEOUT), "the thread body did not run")
	return t, closed
end

local function driver()
	local t, closed = start()
	collectgarbage()
	assert(not closed:wait(PAUSE), "the runtime of an exited thread closed before the thread was stopped")
	t:stop()
	assert(closed:wait(TIMEOUT), "stop did not release the runtime")
	print(PREFIX .. "stopped")

	t, closed = start()
	t = nil
	collectgarbage()
	assert(closed:wait(TIMEOUT), "collecting the thread did not release the runtime")
	print(PREFIX .. "collected")
end

return driver

