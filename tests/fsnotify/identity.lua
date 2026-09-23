--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify identity test (see identity.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"
local WATCHED <const> = SCRATCH .. "/watched"
local FROM    <const> = SCRATCH .. "/from"
local GONE    <const> = SCRATCH .. "/gone"
local BURIED  <const> = SCRATCH .. "/pit/sunk/buried"
local DIRENT  <const> = fs.CREATE | fs.DELETE | fs.MOVED_FROM | fs.MOVED_TO

local function pathof(event)
	local ok, path = pcall(event.path, event)
	return ok and tostring(path) or "raised:" .. tostring(path)
end

local function report(mask, event)
	print(string.format("fsnotify identity: mask=%x name=%s ino=%s dir=%s isdir=%s pid=%s path=%s",
		mask, event:name(), event:ino(), event:dir(), event:isdir(), event:pid(), pathof(event)))
end

local watch = fsnotify.watch(report)
watch:mark(WATCHED, fs.OPEN)
watch:mark(SCRATCH, fs.OPEN | DIRENT)
watch:mark(FROM, fs.RENAME)
watch:mark(GONE, fs.MODIFY)
watch:mark(BURIED, fs.MODIFY)

