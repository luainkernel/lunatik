--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify mask test (see mask.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"
local WIDENED <const> = SCRATCH .. "/widened"
local IGNORED <const> = SCRATCH .. "/ignored"

local function report(mask, event)
	print(string.format("fsnotify mask test: %s mask %x", event:path() or "?", mask))
end

local function check(what, got, expected)
	if got == expected then
		print(string.format("fsnotify mask test pass: %s", what))
	else
		print(string.format("fsnotify mask test fail: %s reads %x, expected %x", what, got, expected))
	end
end

local watch = fsnotify.watch(report)

local widened = watch:mark(WIDENED, fs.OPEN)
check("a mark reads back the mask it was placed with", widened:mask(), fs.OPEN)
check("a mark reads back the mask it was set to", widened:mask(fs.MODIFY), fs.MODIFY)

local ignored = watch:mark(IGNORED, fs.OPEN | fs.MODIFY)
check("a mark reads back an empty ignore mask", ignored:ignore(), 0)
check("a mark reads back the ignore mask it was set to", ignored:ignore(fs.OPEN), fs.OPEN)

