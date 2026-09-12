--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify nomask test (see nomask.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"

local function report(mask)
	if mask == fs.MODIFY then
		print("fsnotify nomask test pass: the callback got FS_MODIFY")
	else
		print(string.format("fsnotify nomask test fail: mask %x", mask))
	end
end

local watch = fsnotify.watch(report)
watch:mark(SCRATCH .. "/watched", fs.MODIFY)

