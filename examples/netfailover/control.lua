--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik  = require("lunatik")
local notifier = require("notifier")
local rcu      = require("rcu")
local netdev   = require("linux.netdev")
local notify   = require("linux.notify")

local NAME <const> = "netfailover" -- the shared table the reactor reads

local events = rcu.table()   -- ifname -> true while the link is down

lunatik._ENV[NAME] = events

local function unpublish()
	lunatik._ENV[NAME] = nil
end

local sentinel = setmetatable({}, {__gc = unpublish})

-- runs under RTNL, where rtnetlink is refused, so the reactor reroutes from its own runtime
local function callback(event, name)
	local _ = sentinel   -- keep the sentinel reachable from the notifier
	if event == netdev.DOWN then
		events[name] = true
	elseif event == netdev.UP then
		events[name] = nil
	end
	return notify.OK
end

notifier.netdevice(callback)

