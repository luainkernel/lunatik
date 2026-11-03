--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the device empty name test (see empty.sh).

local device = require("device")
local test   = require("tests.lib").test

collectgarbage("stop") -- a region a refused device took stays in /proc/devices until the runtime stops

local function refuses(name)
	local ok, err = pcall(device.new, {name = name})
	assert(not ok, string.format("device.new accepted the name %q", name))
	assert(err:match("bad field 'name' %(empty%)"), "device.new raised something else: " .. err)
end

test("device.new refuses an empty name", function()
	refuses("")
end)

test("device.new refuses a name that starts with a NUL byte", function()
	refuses("\0x")
end)

