--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Reports every netdevice event with the index and the namespace of the device
-- it is about, so the shell can tell a device of the initial namespace from a
-- homonymous one elsewhere. See tests/notifier/device_identity.sh.
--

local linux    = require("linux")
local notifier = require("notifier")
local netdev   = require("linux.netdev")
local notify   = require("linux.notify")

local format = string.format

local NETNS <const> = linux.netns()
local events = {[netdev.REGISTER] = "register", [netdev.UNREGISTER] = "unregister"}

print(format("device_identity: netns %d", NETNS))

local function callback(event, name, ifindex, netns)
	local kind = events[event]
	if kind then
		print(format("device_identity: %s %s %d %d %s", kind, name, ifindex, netns,
			netns == NETNS and "own" or "foreign"))
	end
	return notify.OK
end

notifier.netdevice(callback)

