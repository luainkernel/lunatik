--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Child runtime for the notifier stop test (see stop.sh): reports what its own block receives.

local notifier = require("notifier")
local netdev   = require("linux.netdev")
local notify   = require("linux.notify")

local PREFIX <const> = "notifier stop test: child "
local DEVICE <const> = "stop0"

local events = {[netdev.UP] = "up", [netdev.DOWN] = "down"}

local function cb(event, name)
	local kind = events[event]
	if kind ~= nil and name == DEVICE then
		print(PREFIX .. kind .. " " .. name)
	end
	return notify.OK
end

notifier.netdevice(cb)

