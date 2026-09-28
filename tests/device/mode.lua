--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the device mode test (see mode.sh).

local device = require("device")
local stat   = require("linux.stat")
local test   = require("util").test
local format = string.format

local refused  = {name = "lunatik_mode_refused"}
local default  = {name = "lunatik_mode_default"}
local readable = {name = "lunatik_mode_read", mode = stat.IRUGO}

local notnumbers = {"rw", "0644", true}

local function refuses(mode)
	refused.mode = mode
	local ok, err = pcall(device.new, refused)
	assert(not ok, "device.new accepted mode " .. tostring(mode))
	local expected = format("bad field 'mode' %%(number expected, got %s%%)", type(mode))
	assert(err:match(expected), "device.new raised something else: " .. err)
end

collectgarbage("stop") -- a region a refused device took stays in /proc/devices until the runtime stops

test("device.new refuses a mode that is not a number", function()
	for _, mode in ipairs(notnumbers) do
		refuses(mode)
	end
end)

device.new(default)
device.new(readable)

