--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the luathread:task() test, stopped thread case (see task.sh).
--

local lunatik = require("lunatik")

local SCRIPT <const> = "tests/thread/exit"

local spawned = lunatik._ENV.threads[SCRIPT]
spawned:stop()

local t = spawned:task()
local ok, err = pcall(t.pid, t)
assert(not ok, "task():pid() after stop() should raise")
assert(err:match("null pointer dereference"), "task():pid() after stop() raised something else: " .. err)

