--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the luathread:task() test, exited thread case (see task.sh).
--

local lunatik = require("lunatik")

local SCRIPT <const> = "tests/thread/exit"

local t = lunatik._ENV.threads[SCRIPT]:task()
local ok, err = pcall(t.pid, t)
assert(not ok, "task():pid() of an exited thread should raise")
assert(err:match("null pointer dereference"), "task():pid() of an exited thread raised something else: " .. err)

