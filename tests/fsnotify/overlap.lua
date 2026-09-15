--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify overlap test (see overlap.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"
local WATCHED <const> = SCRATCH .. "/watched"

local function report(mask, event)
	print(string.format("fsnotify overlap test note: mask=%x name=%s ino=%s dir=%s pid=%s",
		mask, event:name(), event:ino(), event:dir(), event:pid()))
end

local watch = fsnotify.watch(report)
watch:mark(WATCHED, fs.OPEN)
watch:mark(SCRATCH, fs.OPEN | fs.EVENT_ON_CHILD)

