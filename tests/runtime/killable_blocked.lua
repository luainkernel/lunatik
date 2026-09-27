--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Thread for the killable test (see killable.sh): resumes the devices' runtime until stopped.

local lunatik = require("lunatik")
local thread  = require("thread")
local linux   = require("linux")

local DEVICE <const> = "tests/runtime/killable_device"
local TICK   <const> = 10

local runtimes = lunatik._ENV.runtimes

local function body()
	local runtime = runtimes[DEVICE]
	while not thread.shouldstop() do
		pcall(runtime.resume, runtime)
		linux.schedule(TICK)
	end
end

return body

