--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify inside test (see inside.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH  <const> = "/tmp/lunatik-fsnotify"
local ONESHOT  <const> = SCRATCH .. "/oneshot"
local REMASKED <const> = SCRATCH .. "/remasked"
local UNCACHED <const> = SCRATCH .. "/uncached"
local HALTED   <const> = SCRATCH .. "/halted"
local CREATED  <const> = "created"

local watch
local remasked
local stopper

local function report(mask, event)
	local path = event:path() or "?"
	print(string.format("fsnotify inside test: %s mask %x", path, mask))
	if path == ONESHOT then
		local ok, err = pcall(watch.find, watch, UNCACHED)
		print(string.format("fsnotify inside test: uncached %s", ok and "resolved" or tostring(err)))
		watch:find(ONESHOT):remove()
	elseif path == REMASKED and mask & fs.OPEN ~= 0 then
		remasked:mask(fs.MODIFY)
	elseif event:name() == CREATED then
		local ok, err = pcall(watch.find, watch, UNCACHED)
		print(string.format("fsnotify inside test: locked %s", ok and "resolved" or tostring(err)))
	end
end

local function halt(mask, event)
	print(string.format("fsnotify inside test: halting on %s", event:path() or "?"))
	stopper:stop()
	print("fsnotify inside test: stop returned")
end

watch = fsnotify.watch(report)
watch:mark(ONESHOT, fs.OPEN)
remasked = watch:mark(REMASKED, fs.OPEN)
watch:mark(SCRATCH, fs.CREATE)

stopper = fsnotify.watch(halt)
stopper:mark(HALTED, fs.OPEN)

