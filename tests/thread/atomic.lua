--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread atomic test (see atomic.sh).

local lunatik    = require("lunatik")
local completion = require("completion")
local rcu        = require("rcu")
local test       = require("tests.lib").test

local WAIT    <const> = "tests/thread/wait_body"
local CREATOR <const> = "tests/thread/creator"
local REMOVE  <const> = "tests/thread/remove"
local TIMEOUT <const> = 3000

local function close(context)
	local running, stopped, shared = completion.new(), completion.new(), rcu.table(1)
	local creator = lunatik.runtime(CREATOR)
	creator:resume(lunatik.runtime(WAIT), running, stopped)
	shared.creator = creator
	creator = nil
	collectgarbage() -- the creator's handle and the thread's, so the entry holds the creator alone
	local ran = running:wait(TIMEOUT)
	local remover <close> = lunatik.runtime(REMOVE, context)
	remover:resume(shared)
	local seen = stopped:wait(TIMEOUT)
	assert(ran, "the thread body did not run")
	assert(seen, "the end of the runtime that started a thread, in a " .. context ..
		" runtime's write, did not stop it")
end

local function softirq()
	close("softirq")
end

local function hardirq()
	close("hardirq")
end

local function driver()
	test("softirq", softirq)
	test("hardirq", hardirq)
end

return driver

