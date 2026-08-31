--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the luathread:task() test, running thread case (see task.sh).
--

local thread  = require("thread")
local lunatik = require("lunatik")

local SCRIPT <const> = "tests/thread/dummy"
local NAME <const> = "thread/dummy"

local t = lunatik._ENV.threads[SCRIPT]:task()
assert(t:comm() == NAME, "task():comm() should be the spawned thread's name")
assert(t:pid() ~= thread.current():task():pid(), "task():pid() should not be the caller's pid")
assert(t:pid() == t:tgid(), "a kernel thread leads its own group: pid should equal tgid")

