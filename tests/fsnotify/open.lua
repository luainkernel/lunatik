--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify open test (see open.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"

local function report(mask)
	if mask == fs.OPEN then
		print("fsnotify open test pass: the callback got FS_OPEN")
	else
		print(string.format("fsnotify open test fail: mask %x", mask))
	end
end

local watch = fsnotify.watch(report)
watch:mark(SCRATCH .. "/watched", fs.OPEN)

