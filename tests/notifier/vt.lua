--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier vt test (see vt.sh).

local notifier = require("notifier")
local vt       = require("linux.vt")

local MARK    <const> = string.byte("`") -- the character vt.sh writes
local CONSOLE <const> = 0 -- /dev/tty1
local SPARE   <const> = 62 -- /dev/tty63, the console vt.sh allocates and deallocates

-- the console each event vt.sh causes reaches, and the character a write is told apart by
local events = {
	[vt.PREWRITE]   = {name = "prewrite", console = CONSOLE, c = MARK},
	[vt.WRITE]      = {name = "write", console = CONSOLE, c = MARK},
	[vt.UPDATE]     = {name = "update", console = CONSOLE},
	[vt.ALLOCATE]   = {name = "allocate", console = SPARE},
	[vt.DEALLOCATE] = {name = "deallocate", console = SPARE},
}
local reported = {}

local function report(event, c, console)
	local caused = events[event]
	if caused == nil or console ~= caused.console or (caused.c ~= nil and c ~= caused.c) or reported[event] then
		return
	end
	reported[event] = true
	print("notifier vt: " .. caused.name .. " " .. tostring(c))
end

notifier.vt(report)

