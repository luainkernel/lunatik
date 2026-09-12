--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify lifetime test (see lifetime.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"

local function report(mask)
	print(string.format("fsnotify lifetime test fail: event after stop, mask %x", mask))
end

local watch = fsnotify.watch(report)
watch:mark(SCRATCH .. "/watched", fs.OPEN)
watch:stop()
watch:stop()

local ok, err = pcall(watch.mark, watch, SCRATCH .. "/watched", fs.OPEN)
if ok then
	print("fsnotify lifetime test fail: mark accepted after stop")
elseif not tostring(err):match("null pointer dereference") then
	print("fsnotify lifetime test fail: " .. tostring(err))
else
	print("fsnotify lifetime test pass: a second stop is harmless")
end

