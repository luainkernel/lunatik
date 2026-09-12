--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify sleep test (see sleep.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")
local linux    = require("linux")

local GATED <const> = "/tmp/lunatik-fsnotify/mnt/gated"
local NAP   <const> = 300

local function guard(mask, event)
	linux.schedule(NAP)
	print(string.format("fsnotify sleep test: %s mask %x", event:path() or "?", mask))
	return fsnotify.action.ALLOW
end

local watch = fsnotify.watch(guard)
watch:mark(GATED, fs.OPEN_PERM)

