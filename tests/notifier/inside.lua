--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier inside test (see inside.sh).

local lunatik  = require("lunatik")
local notifier = require("notifier")
local notify   = require("linux.notify")

local PREFIX <const> = "notifier inside test: "
local BODY   <const> = "tests/notifier/inside_body"
local RESUME <const> = "tests/notifier/inside_resume"

local function report(what)
	print(PREFIX .. what)
end

local function nop()
	return notify.OK
end

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "registered" or (tostring(err):gsub("^.-:%d+: ", ""):gsub("%s+$", ""))
end

local function probe()
	return verdict(pcall(notifier.netdevice, nop))
end

local function spawn()
	return verdict(pcall(lunatik.runtime, BODY))
end

local function resume(child)
	return verdict(pcall(child.resume, child))
end

local loading = true
local probed  = false
local lived   = false
local raised  = false
local resumed = {replay = lunatik.runtime(RESUME), live = lunatik.runtime(RESUME)}
local stopper

local function cb()
	if loading and not probed then
		probed = true
		report("replay " .. probe())
		local _, refusal = coroutine.resume(coroutine.create(probe))
		report("coroutine " .. tostring(refusal))
		report("replay runtime " .. spawn())
		report("replay resume " .. resume(resumed.replay))
	elseif not loading and not lived then
		lived = true
		report("live " .. probe())
		report("live runtime " .. spawn())
		report("live resume " .. resume(resumed.live))
	end
	return notify.OK
end

local function stop()
	if stopper then -- the replay reaches this before notifier.netdevice returns
		report("stop")
		stopper:stop()
	end
	return notify.OK
end

local function raiser()
	if not raised then
		raised = true
		error(PREFIX .. "raised", 0) -- a position in the message would fail check_dmesg
	end
	return notify.OK
end

notifier.netdevice(cb)
stopper = notifier.netdevice(stop)
notifier.netdevice(raiser)
loading = false
report("after " .. probe())

