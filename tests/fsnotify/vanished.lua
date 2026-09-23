--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify vanished test (see vanished.sh).

local fsnotify = require("fsnotify")
local device   = require("device")
local fs       = require("linux.fs")

local SCRATCH  <const> = "/tmp/lunatik-fsnotify"
local VANISHED <const> = SCRATCH .. "/vanished"
local MOVED    <const> = SCRATCH .. "/moved"

local function report(mask, event)
	print(string.format("fsnotify vanished test fail: event %x on %s", mask, event:path() or "?"))
end

local function check(what, ok)
	print(string.format("fsnotify vanished test %s: %s", ok and "pass" or "fail", what))
end

local watch = fsnotify.watch(report)
local mark = watch:mark(VANISHED, fs.OPEN)

local trigger = {name = "fsnotify_vanished"}

function trigger:read()
	local ok, err = pcall(mark.mask, mark, fs.MODIFY)
	check("mask raises ENOENT once the path is gone", not ok and tostring(err):match("ENOENT") ~= nil)

	ok, err = pcall(mark.mask, mark)
	check("the handle is dead after the failed re-add",
		not ok and tostring(err):match("null pointer dereference") ~= nil)

	check("the watch no longer marks the moved inode", watch:find(MOVED) == nil)
	return ""
end

device.new(trigger)

