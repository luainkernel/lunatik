--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu spawn test (see percpu_spawn.sh).

local thread  = require("thread")
local linux   = require("linux")
local lunatik = require("lunatik")

local bound <const> = "percpu_spawn:" .. lunatik.cpu()
local env = lunatik._ENV

return function()
	while not thread.shouldstop() do
		env[bound] = thread.current():task().cpu == lunatik.cpu()
		linux.schedule(100)
	end
end

