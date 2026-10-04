--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the method class check test, notifier:stop (see foreign_method.sh).

local notifier = require("notifier")
local test     = require("tests.lib").test
local check    = require("tests.runtime.check")

local function nop() end

test("notifier:stop refuses an object of another class", function()
	local n = notifier.netdevice(nop)
	check.refused("notifier:stop", getmetatable(n).stop)
	n:stop()
end)

