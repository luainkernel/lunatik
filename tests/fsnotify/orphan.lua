--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify lifetime test (see lifetime.sh): a watch
-- that is never stopped, so its group is released from the object's release.

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"

local function report(mask)
	print(string.format("fsnotify orphan test note: mask %x", mask))
end

local watch = fsnotify.watch(report)
watch:mark(SCRATCH .. "/watched", fs.OPEN)
print("fsnotify orphan test pass: watch armed and left to its release")

