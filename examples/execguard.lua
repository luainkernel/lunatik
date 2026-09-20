--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- An allowlist for exec over one directory: the mark is on that directory's
-- inode, where a mount or superblock mark would deny across a whole filesystem,
-- the programs that undo the rule included.

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")
local set      = require("set")

local format = string.format

local SCOPE <const> = "/tmp/lunatik-execguard"

local allowed = set.new({"true", "false"})

local function guard(_, event)
	local name = event:name()

	if allowed:has(name) then
		return fsnotify.action.ALLOW
	end

	print(format("execguard: denied %s to pid %d", name, event:pid()))
	return fsnotify.action.DENY
end

local watch = fsnotify.watch(guard)
watch:mark(SCOPE, fs.OPEN_EXEC_PERM | fs.EVENT_ON_CHILD)

