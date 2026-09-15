--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify reentrancy and thread tests (see
-- reentrancy.sh and thread.sh): a second runtime marking the same file, so its
-- own lock is never the one the guarded runtime holds.

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"

local function report(mask)
	print(string.format("fsnotify observer test note: mask %x", mask))
end

local watch = fsnotify.watch(report)
watch:mark(SCRATCH .. "/watched", fs.OPEN)

