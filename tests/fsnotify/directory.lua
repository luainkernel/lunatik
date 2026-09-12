--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify directory test (see directory.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local MOUNT  <const> = "/tmp/lunatik-fsnotify/mnt"
local INSIDE <const> = MOUNT .. "/inside"
local LISTED <const> = MOUNT .. "/listed"

local function guard(mask, event)
	local path = event:path() or "?"
	print(string.format("fsnotify directory test: %s mask %x", path, mask))
	if mask & fs.OPEN_PERM ~= 0 and path ~= INSIDE then
		return fsnotify.action.DENY
	elseif mask & fs.ACCESS_PERM ~= 0 and path == LISTED then
		return fsnotify.action.DENY
	end
	return fsnotify.action.ALLOW
end

local watch = fsnotify.watch(guard)
watch:mark(INSIDE, fs.OPEN_PERM | fs.EVENT_ON_CHILD)
watch:mark(LISTED, fs.ACCESS_PERM)

