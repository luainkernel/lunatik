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

local channel  = netlink.channel("linkflap")
local history  = {}  -- ifname -> { transition timestamps }
local flapping = {}  -- ifname -> true while in a flap episode

local function callback(event, name)
	if event ~= netdev.UP and event ~= netdev.DOWN then
		return notify.OK
	end
	local now = linux.time()
	local seen = history[name] or {}
	insert(seen, now)
	while seen[1] and now - seen[1] > WINDOW do
		remove(seen, 1)
	end
	history[name] = seen
	if #seen >= LIMIT and not flapping[name] then
		flapping[name] = true
		channel:multicast(FLAP, message.attrs{[IFNAME] = name, [COUNT] = #seen})
	elseif #seen < LIMIT then
		flapping[name] = nil
	end
	return notify.OK
end

notifier.netdevice(callback)

