--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier lock test (see lock.sh).

local linux    = require("linux")
local notifier = require("notifier")
local rt       = require("netlink.rt")
local netdev   = require("linux.netdev")

local PREFIX <const> = "notifier lock test: "
local DEVICE <const> = "lock0"
local LOOKS  <const> = 200
local PAUSE  <const> = 50 -- ms between two looks for the device

local events = {[netdev.REGISTER] = "register", [netdev.UP] = "up"}

local function report(what)
	print(PREFIX .. what)
end

local function cb(event, name)
	local kind = events[event]
	if kind ~= nil and name == DEVICE then
		report(kind)
	end
end

local function created()
	for _ = 1, LOOKS do
		local ifindex = linux.ifindex(DEVICE)
		if ifindex ~= nil then
			return ifindex
		end
		linux.schedule(PAUSE)
	end
end

local function body()
	local ifindex = created()
	if ifindex == nil then
		report("no device")
		return
	end
	local link <close> = rt.link()
	link:set{ifindex = ifindex, up = true}
	report("set up")
end

notifier.netdevice(cb)

return body

