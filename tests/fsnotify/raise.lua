--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify raise test (see raise.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local RAISED <const> = "/tmp/lunatik-fsnotify/raised"

local function report(mask, event)
	print(string.format("fsnotify raise test: %s mask %x", event:path() or "?", mask))
	error("the callback raised")
end

local watch = fsnotify.watch(report)
watch:mark(RAISED, fs.OPEN)

