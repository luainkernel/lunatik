--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify kinds test (see kinds.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local MOUNT <const> = "/tmp/lunatik-fsnotify/mnt"

local function report(mask, event)
	print(string.format("fsnotify kinds test: mount open %s", event:path() or "?"))
end

local watch = fsnotify.watch(report)
watch:mark(MOUNT, fs.OPEN, "mount")

local ok, err = pcall(watch.mark, watch, MOUNT, fs.OPEN, "device")
err = tostring(err)
if ok then
	print("fsnotify kinds test fail: an invalid kind was accepted")
elseif not (err:match('expected "inode"') and err:match('"sb"')) then
	print("fsnotify kinds test fail: " .. err)
else
	print("fsnotify kinds test pass: an invalid kind names the valid ones")
end

