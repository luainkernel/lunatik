--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread module test (see module.sh).

local lunatik    = require("lunatik")
local thread     = require("thread")
local completion = require("completion")

local BODY    <const> = "tests/thread/module_body"
local NAME    <const> = "lunatik_module"
local PREFIX  <const> = "thread module test: "
local TIMEOUT <const> = 3000

local function driver()
	local go, closed = completion.new(), completion.new()
	thread.run(lunatik.runtime(BODY), NAME, go, closed)
	collectgarbage()
	go:complete()
	assert(closed:wait(TIMEOUT), "the thread's exit did not release its runtime")
	print(PREFIX .. "released")
end

return driver

