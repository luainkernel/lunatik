--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify permission tests (see perm.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local MOUNT <const> = "/tmp/lunatik-fsnotify/mnt"

local function report(mask)
	print(mask)
end

local watch = fsnotify.watch(report)
local ok, err = pcall(watch.mark, watch, MOUNT, fs.OPEN_PERM)
watch:stop()
assert(ok or tostring(err):match("CONFIG_FANOTIFY_ACCESS_PERMISSIONS"), err)

print(string.format("fsnotify permission probe: %s", ok and "supported" or tostring(err)))

