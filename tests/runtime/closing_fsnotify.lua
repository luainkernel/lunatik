--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Process script for the closing test (see closing.sh).

local fsnotify = require("fsnotify")
local verdict  = require("tests.runtime.verdict")

local PREFIX <const> = "closing test: "

local function callback(mask, event)
end

local function watch()
	verdict.report(PREFIX, "fsnotify", pcall(fsnotify.watch, callback))
end

sentinel = setmetatable({}, {__gc = watch})

