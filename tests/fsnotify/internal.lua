--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify internal test (see internal.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fsnotify")

local GATED       <const> = "/tmp/lunatik-fsnotify/mnt/gated"
local EIOCBQUEUED <const> = 529

local function guard(mask, event)
	print(string.format("fsnotify internal test: %s mask %x", event:path() or "?", mask))
	return -EIOCBQUEUED
end

local watch = fsnotify.watch(guard)
watch:mark(GATED, fs.OPEN_PERM)

