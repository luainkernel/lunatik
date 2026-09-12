--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify upgrade test (see upgrade.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local GATED <const> = "/tmp/lunatik-fsnotify/mnt/gated"

local function guard(mask, event)
	print(string.format("fsnotify upgrade test: %s mask %x", event:path() or "?", mask))
	return fsnotify.action.DENY
end

local watch = fsnotify.watch(guard)
local mark = watch:mark(GATED, fs.OPEN)
mark:mask(fs.OPEN_PERM)

