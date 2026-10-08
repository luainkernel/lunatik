--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp re-attach test (see test_xdp.sh).

local xdp    = require("xdp")
local action = require("linux.xdp").action

local function replaced()
	print("xdp reattach test fail: the replaced callback ran")
	return action.DROP
end

local function current()
	print("xdp reattach test pass: re-attach installed the last callback")
	return action.PASS
end

xdp.attach(replaced)
xdp.attach(current)

