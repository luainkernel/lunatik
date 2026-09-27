--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread self_stop test (see self_stop.sh); spawned,
-- since a thread is started from a thread and not from a script body.

local lunatik    = require("lunatik")
local thread     = require("thread")
local completion = require("completion")

local BODY    <const> = "tests/thread/self_stop_body"
local NAME    <const> = "lunatik_self_stop"
local PREFIX  <const> = "thread self_stop test: "
local TIMEOUT <const> = 3000

local function report(what)
	print(PREFIX .. what)
end

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""))
end

local function driver()
	local runtime = lunatik.runtime(BODY)
	local ready = completion.new()
	local t = thread.run(runtime, NAME, ready)
	if ready:wait(TIMEOUT) then
		runtime:resume(t)
	end
	report("driver stop " .. verdict(pcall(t.stop, t)))
	runtime:stop()
end

return driver

