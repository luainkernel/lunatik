--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Child runtime for the notifier inside test (see inside.sh): registers from its body.

local notifier = require("notifier")
local notify   = require("linux.notify")

local function nop()
	return notify.OK
end

notifier.netdevice(nop)

