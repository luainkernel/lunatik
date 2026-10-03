--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier init_dispatch test (see init_dispatch.sh).

local linux    = require("linux")
local notifier = require("notifier")

local LOADING <const> = 200 -- ms the body stays in the script after the registration

local function cb(event, name)
	print("init dispatch: " .. name)
end

notifier.netdevice(cb)
linux.schedule(LOADING)

