--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify deny test (see deny.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local MOUNT     <const> = "/tmp/lunatik-fsnotify/mnt"
local SECRET    <const> = MOUNT .. "/secret"
local PUBLIC    <const> = MOUNT .. "/public"
local EDGE      <const> = MOUNT .. "/edge"
local MAX_ERRNO <const> = 4095

local verdicts = {
	[SECRET] = fsnotify.action.DENY,
	[EDGE]   = -MAX_ERRNO,
}

local function guard(mask, event)
	local path = event:path() or "?"
	print(string.format("fsnotify deny test: %s mask %x", path, mask))
	return verdicts[path] or fsnotify.action.ALLOW
end

local watch = fsnotify.watch(guard)
watch:mark(SECRET, fs.OPEN_PERM)
watch:mark(PUBLIC, fs.OPEN_PERM)
watch:mark(EDGE, fs.OPEN_PERM)

