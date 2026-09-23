--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify context test (see context.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")
local test     = require("util").test

local SCRATCH <const> = "/tmp/lunatik-fsnotify"

local function report(mask)
	print(mask)
end

test("fsnotify.watch refuses a callback that is not a function", function()
	local ok, err = pcall(fsnotify.watch, "not a function")
	assert(not ok, "watch accepted a string")
	assert(tostring(err):match("function expected"), err)
end)

test("mark raises the errno name for a path that does not resolve", function()
	local watch = fsnotify.watch(report)
	local ok, err = pcall(watch.mark, watch, SCRATCH .. "/missing", fs.OPEN)
	watch:stop()
	assert(not ok, "mark accepted a path that does not resolve")
	assert(tostring(err):match("ENOENT"), err)
end)

test("mark takes a permission event, or names the config it needs", function()
	local watch = fsnotify.watch(report)
	local ok, err = pcall(watch.mark, watch, SCRATCH, fs.OPEN_PERM)
	watch:stop()
	assert(ok or tostring(err):match("CONFIG_FANOTIFY_ACCESS_PERMISSIONS"), err)
end)

test("mark refuses an invalid kind", function()
	local watch = fsnotify.watch(report)
	local ok, err = pcall(watch.mark, watch, SCRATCH, fs.OPEN, "device")
	watch:stop()
	assert(not ok, "mark accepted an invalid kind")
	assert(tostring(err):match("invalid option"), err)
end)

test("mask takes a permission event, or names the config it needs and keeps the mark", function()
	local watch = fsnotify.watch(report)
	local mark = watch:mark(SCRATCH, fs.OPEN)
	local ok, err = pcall(mark.mask, mark, fs.OPEN_PERM)
	local mask = mark:mask()
	watch:stop()
	assert(ok or tostring(err):match("CONFIG_FANOTIFY_ACCESS_PERMISSIONS"), err)
	assert(mask == (ok and fs.OPEN_PERM or fs.OPEN), string.format("the mark reads %x", mask))
end)

test("find raises the errno name for a path that does not resolve", function()
	local watch = fsnotify.watch(report)
	local ok, err = pcall(watch.find, watch, SCRATCH .. "/missing")
	watch:stop()
	assert(not ok, "find accepted a path that does not resolve")
	assert(tostring(err):match("ENOENT"), err)
end)

test("find refuses an invalid kind", function()
	local watch = fsnotify.watch(report)
	local ok, err = pcall(watch.find, watch, SCRATCH, "device")
	watch:stop()
	assert(not ok, "find accepted an invalid kind")
	assert(tostring(err):match("invalid option"), err)
end)

test("a runtime takes more than one watch", function()
	local first = fsnotify.watch(report)
	local second = fsnotify.watch(report)
	first:stop()
	second:stop()
end)

test("a watch marks a directory and stops cleanly", function()
	local watch = fsnotify.watch(report)
	watch:mark(SCRATCH, fs.OPEN | fs.EVENT_ON_CHILD)
	watch:stop()
end)

