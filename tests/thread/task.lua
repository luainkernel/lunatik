--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the luathread:task() test (see task.sh).
--

local thread = require("thread")

local t = thread.current():task()
assert(t:pid() > 0, "current():task():pid() should be positive")
assert(type(t:comm()) == "string", "current():task():comm() should be a string")
assert(t:pid() == t:tgid(), "current is single-threaded: pid should equal tgid")

