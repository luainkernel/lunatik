--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.ifindex and linux.hwaddr test (see run.sh).

local linux = require("linux")
local test  = require("tests.lib").test

local pack   = table.pack
local rep    = string.rep
local format = string.format

local LOOPBACK  <const> = "lo"
local LOOPINDEX <const> = 1 -- LOOPBACK_IFINDEX
local ETH_ALEN  <const> = 6
local ABSENT    <const> = "lunatiknodev" -- fits IFNAMSIZ, and no host names a device so
local NOINDEX   <const> = 0 -- the kernel numbers devices from 1

local function none(f, arg)
	local answer = pack(f(arg))
	assert(answer.n == 1 and answer[1] == nil,
		format("%s answered %d values, the first %s", tostring(arg), answer.n, tostring(answer[1])))
end

test("linux.ifindex resolves a device's name to its index", function()
	local index = linux.ifindex(LOOPBACK)
	assert(index == LOOPINDEX, LOOPBACK .. " resolved to " .. tostring(index))
end)

test("linux.ifindex answers nil for a name no device has", function()
	none(linux.ifindex, ABSENT)
end)

test("linux.hwaddr answers a device's address", function()
	local addr = linux.hwaddr(LOOPINDEX)
	assert(addr == rep("\0", ETH_ALEN), LOOPBACK .. " answered " .. #tostring(addr) .. " bytes")
end)

test("linux.hwaddr answers nil for an index no device has", function()
	none(linux.hwaddr, NOINDEX)
end)

