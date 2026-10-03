--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier replay test (see replay.sh).

local notifier = require("notifier")
local netdev   = require("linux.netdev")

local events = {[netdev.REGISTER] = "register", [netdev.UP] = "up", [netdev.UNREGISTER] = "unregister"}

local function cb(event, name, netns, replayed, ifindex)
	local kind = events[event]
	if kind then
		print(string.format("replay: %s %s %s", kind, name, tostring(replayed)))
		print(string.format("index: %s %s %d", kind, name, ifindex))
	end
end

notifier.netdevice(cb)

