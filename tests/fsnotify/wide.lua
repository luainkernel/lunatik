--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify kinds test (see kinds.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local MOUNT <const> = "/tmp/lunatik-fsnotify/mnt"

local function report(mask, event)
	print(string.format("fsnotify kinds test: wide open %s", event:path() or "?"))
end

local function check(what, ok)
	print(string.format("fsnotify kinds test %s: %s", ok and "pass" or "fail", what))
end

local watch = fsnotify.watch(report)
local inode = watch:mark(MOUNT .. "/sub/inside", fs.OPEN)
local mount = watch:mark(MOUNT, fs.OPEN, "mount")
local sb = watch:mark(MOUNT, fs.OPEN, "sb")

check("find returns the inode mark", watch:find(MOUNT .. "/sub/inside") == inode)
check("find returns the mount mark", watch:find(MOUNT, "mount") == mount)
check("find returns the superblock mark", watch:find(MOUNT, "sb") == sb)
check("find returns nil for a kind the watch did not mark", watch:find(MOUNT) == nil)

