--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier vt test (see vt.sh).

local notifier = require("notifier")
local vt       = require("linux.vt")

local MARK    <const> = string.byte("`") -- the character vt.sh writes
local CONSOLE <const> = 0 -- /dev/tty1

local names = { [vt.PREWRITE] = "prewrite", [vt.WRITE] = "write" }
local reported = {}

local function report(event, c, console)
	local name = names[event]
	if name == nil or c ~= MARK or console ~= CONSOLE or reported[name] then
		return
	end
	reported[name] = true
	print("notifier vt: " .. name)
end

notifier.vt(report)

