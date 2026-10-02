--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread module test (see module.sh).

local lunatik    = require("lunatik")
local completion = require("completion")

local BODY    <const> = "tests/thread/module_body"
local CREATOR <const> = "tests/thread/creator"
local PREFIX  <const> = "thread module test: "
local TIMEOUT <const> = 5000

local function driver()
	local go, closed = completion.new(), completion.new()
	local creator = lunatik.runtime(CREATOR)
	creator:resume(lunatik.runtime(BODY), creator, go, closed)
	collectgarbage() -- the thread's runtime and the thread, so the driver holds neither
	go:complete()
	assert(closed:wait(TIMEOUT), "the thread's exit did not release its runtime")
	print(PREFIX .. "released")
end

return driver

