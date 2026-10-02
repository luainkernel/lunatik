--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread rtnl test (see rtnl.sh); spawned, since a
-- thread is started from a thread and not from a script body.

local lunatik  = require("lunatik")
local thread   = require("thread")
local notifier = require("notifier")
local notify   = require("linux.notify")

local SCRIPT <const> = "tests/thread/rtnl"
local BODY   <const> = "tests/thread/rtnl_body"
local NAME   <const> = "lunatik_rtnl"
local PREFIX <const> = "thread rtnl test: "

local function report(what)
	print(PREFIX .. what)
end

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""))
end

local t
local probed = false

local function cb()
	if not probed then
		probed = true
		report("stop " .. verdict(pcall(t.stop, t)))
	end
	return notify.OK
end

local function watch(running)
	t = running
	notifier.netdevice(cb)
	report("held " .. verdict(pcall(t.stop, t)))
end

local function drive()
	local watcher <close> = lunatik.runtime(SCRIPT)
	local runtime = lunatik.runtime(BODY)
	local running = thread.run(runtime, NAME)
	report("watch " .. verdict(pcall(watcher.resume, watcher, running))) -- the stop below runs whatever it raised
	report("after " .. verdict(pcall(running.stop, running)))
	runtime:stop()
end

-- spawned, it drives; resumed by the driver with the thread, it watches from a runtime of its own
local function main(running)
	if running then
		watch(running)
	else
		drive()
	end
end

return main

