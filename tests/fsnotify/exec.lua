--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify exec test (see exec.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local PROG <const> = "/tmp/lunatik-fsnotify/mnt/prog"

local function guard(mask, event)
	print(string.format("fsnotify exec test: %s mask %x", event:path() or "?", mask))
	return fsnotify.action.DENY
end

local watch = fsnotify.watch(guard)
watch:mark(PROG, fs.OPEN_EXEC_PERM)

