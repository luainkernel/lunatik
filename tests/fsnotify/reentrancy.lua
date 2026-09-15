--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify reentrancy test (see reentrancy.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"
local WATCHED <const> = SCRATCH .. "/watched"

local calls = 0

local function report(mask)
	calls = calls + 1
	if calls > 1 then
		print(string.format("fsnotify reentrancy test fail: call %d, mask %x", calls, mask))
		return
	end

	local file = assert(io.open(WATCHED))
	file:close()
	print("fsnotify reentrancy test pass: the callback opened the marked file and returned")
end

local watch = fsnotify.watch(report)
watch:mark(WATCHED, fs.OPEN)

