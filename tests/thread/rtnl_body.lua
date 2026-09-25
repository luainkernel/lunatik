--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Thread body for the thread rtnl test (see rtnl.sh): schedules until stopped.

local thread = require("thread")
local linux  = require("linux")

local TICK <const> = 10

local function body()
	while not thread.shouldstop() do
		linux.schedule(TICK)
	end
end

return body

