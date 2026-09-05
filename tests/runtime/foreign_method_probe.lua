--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the method class check test, probe methods (see foreign_method.sh).

local probe  = require("probe")
local data   = require("data")
local systab = require("syscall.table")
local test   = require("util").test

local foreign = data.new(8)

local function refused(name, method, ...)
	local ok, err = pcall(method, foreign, ...)
	assert(not ok, name .. " accepted a data object")
	assert(err:match("expected"), name .. " raised something else: " .. err)
end

local function nop() end

test("probe methods refuse an object of another class", function()
	local address = next(systab)
	local p = probe.new(systab[address], {pre = nop})
	refused("probe:stop", getmetatable(p).stop)
	refused("probe:enable", getmetatable(p).enable, false)
	p:stop()
end)

