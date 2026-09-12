--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify marks test (see marks.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"
local KEPT    <const> = SCRATCH .. "/kept"
local DROPPED <const> = SCRATCH .. "/dropped"

local function report(mask, event)
	print(string.format("fsnotify marks test: open %s", event:path() or "?"))
end

local function check(what, ok)
	print(string.format("fsnotify marks test %s: %s", ok and "pass" or "fail", what))
end

local watch = fsnotify.watch(report)
local kept = watch:mark(KEPT, fs.OPEN)
local dropped = watch:mark(DROPPED, fs.OPEN)

check("find returns the mark the watch placed", watch:find(KEPT) == kept)
check("find returns nil where the watch has no mark", watch:find(SCRATCH) == nil)

local ok, err = pcall(watch.mark, watch, KEPT, fs.OPEN)
check("a second mark on the same object is refused", not ok and tostring(err):match("EEXIST") ~= nil)

dropped:remove()
check("find returns nil for a removed mark", watch:find(DROPPED) == nil)

