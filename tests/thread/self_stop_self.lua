--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Spawned by the thread self_stop test (see self_stop.sh): its body stops its own script.

local lunatik = require("lunatik")
local runner  = require("lunatik.runner")
local thread  = require("thread")
local linux   = require("linux")

local SCRIPT <const> = "tests/thread/self_stop_self"
local PREFIX <const> = "thread self_stop test: "
local TICK   <const> = 10

local threads = lunatik._ENV.threads

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""))
end

local function body()
	while threads[SCRIPT] == nil and not thread.shouldstop() do -- spawn stores the thread once it started
		linux.schedule(TICK)
	end
	print(PREFIX .. "self stop " .. verdict(pcall(runner.stop, SCRIPT)))
end

return body

