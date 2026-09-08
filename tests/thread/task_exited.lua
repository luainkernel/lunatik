--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the luathread:task() test, exited thread case (see task.sh).
--

local lunatik = require("lunatik")

local SCRIPT <const> = "tests/thread/exit"

local t = lunatik._ENV.threads[SCRIPT]:task()
assert(t:pid() > 0, "task():pid() of an exited thread should still report it")
assert(type(t:comm()) == "string", "task():comm() of an exited thread should still report it")

