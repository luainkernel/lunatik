--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the device mode test (see mode.sh).

local device = require("device")
local stat   = require("linux.stat")
local test   = require("tests.lib").test
local format = string.format

local refused  = {name = "lunatik_mode_refused"}
local default  = {name = "lunatik_mode_default"}
local readable = {name = "lunatik_mode_read", mode = stat.IRUGO}
local special  = {name = "lunatik_mode_special", mode = stat.ISUID | stat.ISGID | stat.ISVTX | stat.IRUGO}

local notnumbers = {"rw", "0644", true}
-- a file type over the permissions, which devtmpfs ORs with S_IFCHR into S_IFBLK, and the bits past S_IALLUGO
local pastrange  = {stat.IFDIR | stat.IRUGO, stat.IALLUGO + 1, -1}

local function refuses(mode, expected)
	refused.mode = mode
	local ok, err = pcall(device.new, refused)
	assert(not ok, "device.new accepted mode " .. tostring(mode))
	assert(err:match(expected), "device.new raised something else: " .. err)
end

collectgarbage("stop") -- a region a refused device took stays in /proc/devices until the runtime stops

test("device.new refuses a mode that is not a number", function()
	for _, mode in ipairs(notnumbers) do
		refuses(mode, format("bad field 'mode' %%(number expected, got %s%%)", type(mode)))
	end
end)

test("device.new refuses a mode past S_IALLUGO", function()
	for _, mode in ipairs(pastrange) do
		refuses(mode, "bad field 'mode' %(out of bounds%)")
	end
end)

device.new(default)
device.new(readable)
device.new(special)

