--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the closing test (see closing.sh).

local lunatik = require("lunatik")

local OBJECTS <const> = "tests/runtime/closing_objects"
local THREAD  <const> = "tests/runtime/closing_thread"
local WAIT    <const> = "tests/runtime/closing_completion"
local CASE    <const> = "tests/runtime/closing.case"
local OPENED  <const> = "tests/runtime/closing.opened"
local CLOSED  <const> = "tests/runtime/closing.closed"
local PREFIX  <const> = "closing test: "

local env = lunatik._ENV

-- numbered as closing_objects.lua names them
local cases = {clone = 1, resume = 2, runtime = 3, percpu = 4}

local function start(name)
	env[CASE] = cases[name]
	env[OPENED] = 0
	env[CLOSED] = 0
end

local function report(name)
	local opened = env[OPENED]
	local open = opened - env[CLOSED]
	local left = open == 0 and "released" or "left " .. open .. " of " .. opened .. " open"
	print(PREFIX .. name .. " " .. (opened == 0 and "opened none" or left))
end

local function stopped(name)
	start(name)
	lunatik.runtime(OBJECTS):stop()
	report(name)
end

local function collected(name)
	start(name)
	lunatik.runtime(OBJECTS)
	collectgarbage()
	report(name .. " collected")
end

stopped("clone")
stopped("resume")
stopped("runtime")
stopped("percpu")
collected("clone")

env[CASE] = nil
env[OPENED] = nil
env[CLOSED] = nil

lunatik.runtime(THREAD)
lunatik.runtime(WAIT)
collectgarbage()

