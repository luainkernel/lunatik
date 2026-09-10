--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Prints every device the netdevice chain reports as registered, from a block
-- registered after chain_continues_held's. See tests/notifier/chain_continues.sh.

local notifier = require("notifier")
local netdev   = require("linux.netdev")
local notify   = require("linux.notify")

local function callback(event, name)
	if event == netdev.REGISTER then
		print("chain continues: register " .. name)
	end
	return notify.OK
end

notifier.netdevice(callback)

