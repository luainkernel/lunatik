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
local RESOLVER <const> = SCRATCH .. "/resolver"
local MARKED   <const> = SCRATCH .. "/marked"
local OTHER    <const> = SCRATCH .. "/other"
local HALTED   <const> = SCRATCH .. "/halted"
local CREATED  <const> = "created"

local watch
local remasked
local other
local othermark
local stopper

local function outcome(what, ok, err)
	print(string.format("fsnotify inside test: %s %s", what, ok and "resolved" or tostring(err)))
end

local function report(mask, event)
	local path = event:path() or "?"
	print(string.format("fsnotify inside test: %s mask %x", path, mask))
	if path == ONESHOT then
		outcome("uncached", pcall(watch.find, watch, UNCACHED))
		watch:find(ONESHOT):remove()
	elseif path == REMASKED and mask & fs.OPEN ~= 0 then
		remasked:mask(fs.MODIFY)
	elseif path == RESOLVER then
		outcome("mark uncached", pcall(watch.mark, watch, UNCACHED, fs.OPEN))
		outcome("mark cached", pcall(watch.mark, watch, MARKED, fs.OPEN))
		outcome("other uncached", pcall(other.find, other, UNCACHED))
		local ok, found = pcall(other.find, other, OTHER)
		outcome("other cached", ok and found == othermark, found)
	elseif event:name() == CREATED then
		outcome("locked", pcall(watch.find, watch, UNCACHED))
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
watch:mark(RESOLVER, fs.OPEN)
watch:mark(SCRATCH, fs.CREATE)

other = fsnotify.watch(report)
othermark = other:mark(OTHER, fs.OPEN)

stopper = fsnotify.watch(halt)
stopper:mark(HALTED, fs.OPEN)

