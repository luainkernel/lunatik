--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Process script for the closing test (see closing.sh).

local thread  = require("thread")
local verdict = require("tests.runtime.verdict")

local PREFIX <const> = "closing test: "

local function run()
	verdict.report(PREFIX, "thread", pcall(thread.run))
end

sentinel = setmetatable({}, {__gc = run})

