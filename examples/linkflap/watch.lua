--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Detects link flapping inside the kernel. A notifier.netdevice callback keeps a
-- per-interface sliding window of UP/DOWN transitions and, once one interface
-- crosses the threshold within the window, multicasts a structured flapping
-- event (interface name and transition count) over the "linkflap" generic
-- netlink family. Consume it in userspace with examples/linkflap/subscriber.c.

local linux    = require("linux")
local notifier = require("notifier")
local netlink  = require("netlink")
local message  = require("netlink.message")
local netdev   = require("linux.netdev")
local notify   = require("linux.notify")

local insert = table.insert
local remove = table.remove

local WINDOW <const> = 10 * 1000000000  -- 10s in nanoseconds
local LIMIT  <const> = 5                -- transitions within WINDOW to flag flapping
local FLAP   <const> = 1                -- channel genl command
local IFNAME <const> = 1                -- event attribute types
local COUNT  <const> = 2
local home   <const> = linux.netns()    -- the namespace the announced names belong to

local channel  = netlink.channel("linkflap")
local history  = {}  -- ifname -> { transition timestamps }
local flapping = {}  -- ifname -> true while in a flap episode

local transitions = {[netdev.UP] = true, [netdev.DOWN] = true}

local function record(name)
	local now = linux.time()
	local seen = history[name] or {}
	insert(seen, now)
	while now - seen[1] > WINDOW do
		remove(seen, 1)
	end
	history[name] = seen
	return #seen
end

local function announce(name, count)
	channel:multicast(FLAP, message.attrs{[IFNAME] = name, [COUNT] = count})
end

local function callback(event, name, netns)
	if netns ~= home then -- the event carries the name alone, which another namespace can repeat
		return notify.OK
	end
	if transitions[event] then
		local count = record(name)
		if count < LIMIT then
			flapping[name] = nil
		elseif not flapping[name] then
			flapping[name] = true
			announce(name, count)
		end
	end
	return notify.OK
end

notifier.netdevice(callback)

