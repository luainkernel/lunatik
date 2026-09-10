--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Registers a netdevice notifier and holds its own teardown from a finalizer,
-- so the block is still registered while the runtime cannot take an event.
-- See tests/notifier/chain_continues.sh.

local linux    = require("linux")
local notifier = require("notifier")
local notify   = require("linux.notify")

local HOLD <const> = 5000

local function callback()
	return notify.OK
end

local function hold()
	linux.schedule(HOLD)
end

notifier.netdevice(callback)
sentinel = setmetatable({}, {__gc = hold})

