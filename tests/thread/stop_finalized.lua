--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Thread body for the thread stop test (see stop.sh): its runtime's close stops the thread again.

local THREAD  <const> = "thread"
local STOPPED <const> = "stopped"

local function stop(shared)
	return shared[THREAD]:stop()
end

local function close(sentinel)
	local shared = sentinel.shared
	local ok, stopped = pcall(stop, shared)
	shared[STOPPED] = ok and stopped
end

local function body(shared, running)
	sentinel = setmetatable({shared = shared}, {__gc = close})
	running:complete()
end

return body

