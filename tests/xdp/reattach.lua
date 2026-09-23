--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp re-attach test (see test_xdp.sh).

local xdp    = require("xdp")
local action = require("linux.xdp")

local function replaced(ctx)
	print("xdp reattach test fail: the replaced callback ran")
	ctx:action(action.DROP)
end

local function current(ctx)
	print("xdp reattach test pass: re-attach installed the last callback")
	ctx:action(action.PASS)
end

xdp.attach(replaced)
xdp.attach(current)

