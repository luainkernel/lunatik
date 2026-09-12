--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify child test (see child.sh): a directory
-- mark without FS_EVENT_ON_CHILD, which reports the directory and not its files.

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"

local function report(mask)
	if mask == fs.OPEN | fs.ISDIR then
		print("fsnotify nochild test pass: the callback got FS_OPEN for the directory itself")
	else
		print(string.format("fsnotify nochild test fail: mask %x", mask))
	end
end

local watch = fsnotify.watch(report)
watch:mark(SCRATCH, fs.OPEN)

