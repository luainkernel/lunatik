--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Child script for the deferred test (see deferred.sh): its finalizer sleeps as it closes.

local linux = require("linux")
local task  = require("task")

local PAUSE <const> = 1 -- ms

local function finalize()
	linux.schedule(PAUSE)
	print("deferred test: slept on " .. task.current():comm())
end

sentinel = setmetatable({}, {__gc = finalize})

