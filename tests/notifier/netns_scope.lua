--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier namespace test (see netns_scope.sh).

local notifier = require("notifier")
local netdev   = require("linux.netdev")
local notify   = require("linux.notify")

local events = {[netdev.REGISTER] = "register", [netdev.UNREGISTER] = "unregister"}

local function cb(event, name)
	local kind = events[event]
	if kind then
		print("netns scope: " .. kind .. " " .. name)
	end
	return notify.OK
end

notifier.netdevice(cb)

