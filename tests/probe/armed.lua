--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the armed-runtime test (see armed.sh).

local probe = require("probe")

local SYMBOL <const> = "vfs_read"
local ARMED <const> = "not allowed after module load"

local handle
local done = false

local function refused(what, method, ...)
	local ok, err = pcall(method, ...)
	if not ok and type(err) == "string" and err:find(ARMED, 1, true) then
		print("probe armed: " .. what)
	end
end

local function pre()
	if done then
		return
	end
	done = true

	refused("new", probe.new, SYMBOL, {})
	refused("stop", handle.stop, handle)
	refused("enable", handle.enable, handle, false)
end

local spare = probe.new(SYMBOL, {})
spare:enable(false)
spare:enable(true)
spare:stop()
print("probe loading: new, enable and stop")

handle = probe.new(SYMBOL, {pre = pre})

