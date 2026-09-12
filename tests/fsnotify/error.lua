--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify error test (see error.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local GATED <const> = "/tmp/lunatik-fsnotify/mnt/gated"

local function guard(mask, event)
	print(string.format("fsnotify error test: %s mask %x", event:path() or "?", mask))
	error("the guard raised")
end

local watch = fsnotify.watch(guard)
watch:mark(GATED, fs.OPEN_PERM)

