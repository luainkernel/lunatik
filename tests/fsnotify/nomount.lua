--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify kinds test (see kinds.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local MOUNT   <const> = "/tmp/lunatik-fsnotify/mnt"
local REFUSAL <const> = "\"mount\" needs kernel 6.10 or later"

local function report(mask, event)
	print(string.format("fsnotify kinds test: nomount open %s", event:path() or "?"))
end

local function check(what, ok, err)
	if ok then
		print(string.format("fsnotify kinds test fail: %s accepted the mount kind", what))
	elseif not tostring(err):find(REFUSAL, 1, true) then
		print(string.format("fsnotify kinds test fail: %s raised %s", what, tostring(err)))
	else
		print(string.format("fsnotify kinds test pass: %s refuses the mount kind", what))
	end
end

local watch = fsnotify.watch(report)
check("mark", pcall(watch.mark, watch, MOUNT, fs.OPEN, "mount"))
check("find", pcall(watch.find, watch, MOUNT, "mount"))

