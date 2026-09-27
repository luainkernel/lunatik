--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Waiter for the killable test (see killable.sh): waits on the holder's locks until stopped.

local lunatik = require("lunatik")
local thread  = require("thread")
local linux   = require("linux")
local verdict = require("tests.runtime.verdict")

local HOLDER <const> = "tests/runtime/killable_holder"
local KEY    <const> = "killable_set"
local HELD   <const> = "killable_held"
local NAME   <const> = "lunatik_killable"
local PREFIX <const> = "killable test: thread "
local TICK   <const> = 10

local env = lunatik._ENV

local function body()
	while not env[HELD] and not thread.shouldstop() do
		linux.schedule(TICK)
	end
	local runtime = env.runtimes[HOLDER]
	local set = env[KEY]
	verdict.report(PREFIX, "resume", pcall(runtime.resume, runtime))
	verdict.report(PREFIX, "run", pcall(thread.run, runtime, NAME))
	verdict.report(PREFIX, "stop", pcall(runtime.stop, runtime))
	verdict.report(PREFIX, "percpu resume", pcall(set.resume, set))
	verdict.report(PREFIX, "percpu stop", pcall(set.stop, set))
end

return body

