--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Thread body for the thread stop test (see stop.sh): it outlasts its stop until the driver releases it.

local thread = require("thread")
local linux  = require("linux")
local task   = require("linux.task")

local RELEASED <const> = "released"
local LINGERED <const> = "lingered"
local TICK     <const> = 10
local TICKS    <const> = 300

local function released(shared)
	return shared[RELEASED]
end

local function await(state, done, ...)
	for _ = 1, TICKS do
		if done(...) then
			return true
		end
		linux.schedule(TICK, state)
	end
	return false
end

local function body(shared, running, stopping)
	running:complete()
	if await(task.INTERRUPTIBLE, thread.shouldstop) then
		stopping:complete()
		shared[LINGERED] = await(task.UNINTERRUPTIBLE, released, shared) -- a stop ends an interruptible sleep at once
	end
end

return body

