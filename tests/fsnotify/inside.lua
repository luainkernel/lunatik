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

local watch
local remasked

local function report(mask, event)
	local path = event:path() or "?"
	print(string.format("fsnotify inside test: %s mask %x", path, mask))
	if path == ONESHOT then
		watch:find(ONESHOT):remove()
	elseif path == REMASKED and mask & fs.OPEN ~= 0 then
		remasked:mask(fs.MODIFY)
	end
end

watch = fsnotify.watch(report)
watch:mark(ONESHOT, fs.OPEN)
remasked = watch:mark(REMASKED, fs.OPEN)

