--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the self_stop test (see self_stop.sh).

local lunatik = require("lunatik")
local runner  = require("lunatik.runner")
local device  = require("device")
local thread  = require("thread")

local SCRIPT <const> = "tests/runtime/self_stop"
local CHILD  <const> = "tests/runtime/self_stop_child"
local OTHER  <const> = "tests/runtime/self_stop_other"
local NAME   <const> = "lunatik_self_stop"
local PREFIX <const> = "self_stop test: "

local runtimes = lunatik._ENV.runtimes

local function report(what)
	print(PREFIX .. what)
end

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""))
end

local function open(name)
	local file = io.open("/dev/" .. name)
	if file then
		file:close()
	end
	return file and "accepted" or "refused"
end

local driver = {name = NAME}

-- a file operation runs under the lock of the runtime that made the device
function driver:read()
	local runtime = runtimes[SCRIPT]
	report("fop stop " .. verdict(pcall(runtime.stop, runtime)))
	report("fop resume " .. verdict(pcall(runtime.resume, runtime)))
	report("fop thread " .. verdict(pcall(thread.run, runtime, NAME)))
	report("fop open own " .. open(NAME))
	report("fop open other " .. open(NAME .. "_other"))
	return ""
end

device.new(driver)
runner.run(OTHER)

local runtime = lunatik.runtime(CHILD)
runtime:resume(runtime)
report("body stop " .. verdict(pcall(runtime.stop, runtime)))

local set = lunatik.percpu(CHILD)
set:resume(set)
report("body stop " .. verdict(pcall(set.stop, set)))

