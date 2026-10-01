--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the method class check test, probe methods (see foreign_method.sh).

local probe  = require("probe")
local systab = require("syscall.table")
local test   = require("util").test
local check  = require("tests.runtime.check")

local function nop() end

test("probe methods refuse an object of another class", function()
	local address = next(systab)
	local p = probe.new(systab[address], {pre = nop})
	check.refused("probe:stop", getmetatable(p).stop)
	check.refused("probe:enable", getmetatable(p).enable)
	check.refused("probe:disable", getmetatable(p).disable)
	p:stop()
end)

