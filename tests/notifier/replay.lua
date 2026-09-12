--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier replay test (see replay.sh).

local notifier = require("notifier")
local netdev   = require("linux.netdev")
local notify   = require("linux.notify")

local events = {[netdev.REGISTER] = "register", [netdev.UP] = "up", [netdev.UNREGISTER] = "unregister"}

local function cb(event, name, replayed)
	local kind = events[event]
	if kind then
		print(string.format("replay: %s %s %s", kind, name, tostring(replayed)))
	end
	return notify.OK
end

notifier.netdevice(cb)

