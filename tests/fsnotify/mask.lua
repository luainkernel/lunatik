--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify mask test (see mask.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fsnotify")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"
local WIDENED <const> = SCRATCH .. "/widened"
local IGNORED <const> = SCRATCH .. "/ignored"
local U32_MAX <const> = 0xffffffff
local PAST32  <const> = 1 << 32

local OUTOFBOUNDS <const> = "out of bounds"

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

local function refuses(what, f, ...)
	local ok, err = pcall(f, ...)
	if not ok and err:find(OUTOFBOUNDS, 1, true) then
		print(string.format("fsnotify mask test pass: %s", what))
	else
		print(string.format("fsnotify mask test fail: %s: %s", what, ok and "accepted" or err))
	end
end

local watch = fsnotify.watch(report)
refuses("a mark refuses a mask past 32 bits", watch.mark, watch, SCRATCH, PAST32 | fs.OPEN)
refuses("a mark refuses a negative mask", watch.mark, watch, SCRATCH, -1)

local widened = watch:mark(WIDENED, fs.OPEN)
check("a mark reads back the mask it was placed with", widened:mask(), fs.OPEN)
check("a mark reads back an empty mask it was set to", widened:mask(0), 0)
check("a mark reads back the mask it was set to", widened:mask(fs.MODIFY), fs.MODIFY)
refuses("a mark's mask refuses one past 32 bits", widened.mask, widened, PAST32 | fs.OPEN)
refuses("a mark's mask refuses a negative one", widened.mask, widened, -1)
check("a refused mask leaves the mark's", widened:mask(), fs.MODIFY)

local ignored = watch:mark(IGNORED, fs.OPEN | fs.MODIFY)
check("a mark reads back an empty ignore mask", ignored:ignore(), 0)
check("a mark reads back an ignore mask of all 32 bits", ignored:ignore(U32_MAX), U32_MAX)
check("a mark reads back an empty ignore mask it was set to", ignored:ignore(0), 0)
check("a mark reads back the ignore mask it was set to", ignored:ignore(fs.OPEN), fs.OPEN)
refuses("a mark's ignore mask refuses one past 32 bits", ignored.ignore, ignored, PAST32 | fs.MODIFY)
refuses("a mark's ignore mask refuses a negative one", ignored.ignore, ignored, -1)
check("a refused ignore mask leaves the mark's", ignored:ignore(), fs.OPEN)

