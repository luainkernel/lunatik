--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the undispatched runtime test (see miss.sh).

local xdp    = require("xdp")
local action = require("linux.xdp")

local function test_miss(ctx)
	ctx:action(action.PASS)
end

xdp.attach(test_miss)

