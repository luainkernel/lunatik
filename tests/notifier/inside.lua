--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier inside test (see inside.sh).

local lunatik  = require("lunatik")
local notifier = require("notifier")
local channel  = require("netlink.channel")
local rt       = require("netlink.rt")

local PREFIX <const> = "notifier inside test: "
local BODY   <const> = "tests/notifier/inside_body"
local RESUME <const> = "tests/notifier/inside_resume"
local LIVE   <const> = "inside1"
local FAMILY <const> = "lunatik_inside"

local function report(what)
	print(PREFIX .. what)
end

local function nop() end

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""):gsub("%s+$", ""))
end

local function register()
	notifier.netdevice(nop):stop()
end

local function request()
	local link <close> = rt.link()
	link:list()
end

local function family()
	channel.new(FAMILY):stop()
end

local function spawn()
	lunatik.runtime(BODY):stop()
end

local function resume()
	local child = lunatik.runtime(RESUME)
	child:resume()
	child:stop()
end

local function probe(where)
	report(where .. " register " .. verdict(pcall(register)))
	report(where .. " request " .. verdict(pcall(request)))
	report(where .. " family " .. verdict(pcall(family)))
	report(where .. " runtime " .. verdict(pcall(spawn)))
	report(where .. " resume " .. verdict(pcall(resume)))
end

local probed = {}

local function cb(event, name, netns, replayed)
	local where = replayed and "replay" or name == LIVE and "live" or nil
	if where ~= nil and not probed[where] then
		probed[where] = true
		probe(where)
	end
end

local stopper

local function stop()
	report("stop")
	stopper:stop()
end

local raised = false
local delivered = false

local function raiser()
	if not raised then
		raised = true
		error(PREFIX .. "raised", 0) -- a position in the message would fail check_dmesg
	elseif not delivered then
		delivered = true
		report("delivered after a raise")
	end
end

notifier.netdevice(cb)
stopper = notifier.netdevice(stop)
notifier.netdevice(raiser)

