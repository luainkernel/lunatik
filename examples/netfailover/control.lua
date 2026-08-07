--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik  = require("lunatik")
local notifier = require("notifier")
local rcu      = require("rcu")
local netdev   = require("linux.netdev")
local notify   = require("linux.notify")

local events = rcu.table()   -- ifname -> "down" (nil = up)

lunatik._ENV["netfailover"] = events

-- the netdevice callback runs holding rtnl_lock, so it must not issue rtnetlink
-- itself (that self-deadlocks); it only records the link state, which the
-- separately spawned reactor reprograms routing from without the lock held
local sentinel = setmetatable({}, {__gc = function()
	lunatik._ENV["netfailover"] = nil
end})

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

