--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify marks test (see marks.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"

local function report(mask, event)
	print(string.format("fsnotify marks test fail: event after stop, %s", event:path() or "?"))
end

local watch = fsnotify.watch(report)
local kept = watch:mark(SCRATCH .. "/kept", fs.OPEN)
watch:mark(SCRATCH .. "/dropped", fs.OPEN)
watch:stop()

local ok, err = pcall(kept.mask, kept, fs.MODIFY)
err = tostring(err)
if ok then
	print("fsnotify marks test fail: a mark outlived the watch that placed it")
elseif not err:match("null pointer dereference") then
	print("fsnotify marks test fail: " .. err)
else
	print("fsnotify marks test pass: stop takes every mark with it")
end

