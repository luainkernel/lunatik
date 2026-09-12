--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side kthread body for the fsnotify thread test (see thread.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")
local linux    = require("linux")
local thread   = require("thread")

local WATCHED <const> = "/tmp/lunatik-fsnotify/watched"

local function report(mask)
	print(string.format("fsnotify thread test fail: the callback ran, mask %x", mask))
end

local function body()
	local file = assert(io.open(WATCHED))
	file:close()
	print("fsnotify thread test pass: the open returned inside the thread body")
	while not thread.shouldstop() do
		linux.schedule(100)
	end
end

local watch = fsnotify.watch(report)
watch:mark(WATCHED, fs.OPEN)

return body

