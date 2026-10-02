--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Script for the closing test, run in every context (see closing.sh).

local completion = require("completion")
local verdict    = require("tests.runtime.verdict")

local PREFIX  <const> = "closing test: "
local TIMEOUT <const> = 10 -- ms

local event = completion.new()

sentinel = setmetatable({}, {__gc = function()
	verdict.report(PREFIX, "completion", pcall(event.wait, event, TIMEOUT))
end})

