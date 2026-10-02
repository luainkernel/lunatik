--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Waits in a thread body for that thread's stop, for the thread tests (see run.sh).

local thread = require("thread")
local linux  = require("linux")

local TIMEOUT <const> = 3000

local wait = {}

-- waits three seconds at most, and completes `stopped` when the stop came
function wait.stop(stopped)
	linux.schedule(TIMEOUT) -- a stop ends the sleep at once
	if thread.shouldstop() then
		stopped:complete()
	end
end

return wait

