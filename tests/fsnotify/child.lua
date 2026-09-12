--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify child test (see child.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"

local function report(mask)
	if mask == fs.OPEN | fs.EVENT_ON_CHILD then
		print("fsnotify child test pass: the callback got FS_OPEN tagged FS_EVENT_ON_CHILD")
	else
		print(string.format("fsnotify child test fail: mask %x", mask))
	end
end

local watch = fsnotify.watch(report)
watch:mark(SCRATCH, fs.OPEN | fs.EVENT_ON_CHILD)

