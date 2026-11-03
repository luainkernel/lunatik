--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the device name test (see name.sh).

local device = require("device")
local format = string.format

local empties = {"", "\0x"}

collectgarbage("stop") -- a region a refused device took stays in /proc/devices until the runtime stops

for _, name in ipairs(empties) do
	local ok, err = pcall(device.new, {name = name})
	assert(not ok and err:match("bad field 'name' %(empty%)"), format("device.new took the name %q: %s", name, err))
end

device.new({name = "lunatik%%device"})

