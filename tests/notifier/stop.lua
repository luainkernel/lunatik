--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier stop test (see stop.sh).

local lunatik  = require("lunatik")
local runner   = require("lunatik.runner")
local notifier = require("notifier")
local netdev   = require("linux.netdev")
local notify   = require("linux.notify")

local PREFIX <const> = "notifier stop test: "
local CHILD  <const> = "tests/notifier/stop_child"
local PLAIN  <const> = "tests/notifier/inside_resume"
local DEVICE <const> = "stop0"

local function report(what)
	print(PREFIX .. what)
end

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""):gsub("%s+$", ""))
end

local loading = true
local probed  = false
local child   = runner.run(CHILD) -- before the script's block, so the replay has a child to stop
local set     = lunatik.percpu(PLAIN) -- block-less runtimes: a build without the refusal closes them without wedging

local function stop(runtime)
	return verdict(pcall(runtime.stop, runtime))
end

local function scope(runtime)
	local held <close> = runtime
end

local function close(runtime)
	return verdict(pcall(scope, runtime))
end

local function probe(where)
	report(where .. " stop " .. stop(child))
	report(where .. " close " .. close(child))
	report(where .. " percpu stop " .. stop(set))
	report(where .. " percpu close " .. close(set))
end

local function cb(event, name)
	if loading and not probed then
		probed = true
		probe("replay")
	elseif not loading and name == DEVICE and event == netdev.UP then
		probe("live")
	end
	return notify.OK
end

notifier.netdevice(cb)
loading = false

local plain = lunatik.runtime(PLAIN) -- holds no block: its registration waits for a resume that never comes
report("after stop " .. stop(plain))
report("after percpu stop " .. stop(set))

