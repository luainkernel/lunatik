--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify kinds test (see kinds.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local MOUNT <const> = "/tmp/lunatik-fsnotify/mnt"

local function report(mask, event)
	print(string.format("fsnotify kinds test: sb open %s", event:path() or "?"))
end

local watch = fsnotify.watch(report)
watch:mark(MOUNT, fs.OPEN, "sb")

