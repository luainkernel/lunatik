--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- An allowlist for exec, over one directory and nothing else.
--
-- The mark is an inode mark on SCOPE carrying EVENT_ON_CHILD, so the only exec
-- this rule can refuse is of an entry directly inside that directory. It is
-- never a system-wide default deny: a "mount" or "sb" mark reaches every file
-- of a mount or of a whole filesystem, and a rule that denies there leaves the
-- machine unable to run the programs that would undo it.

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")
local set      = require("set")

local format = string.format

local SCOPE <const> = "/tmp/lunatik-execguard"

local allowed = set.new({"true", "false"})

local function guard(_, event)
	local name = event:name()

	-- an event carrying no entry name is not one of SCOPE's children: allow it,
	-- as everything this rule cannot match is allowed
	if name == nil or allowed:has(name) then
		return fsnotify.action.ALLOW
	end

	print(format("execguard: denied %s to pid %d", name, event:pid()))
	return fsnotify.action.DENY
end

local watch = fsnotify.watch(guard)
watch:mark(SCOPE, fs.OPEN_EXEC_PERM | fs.EVENT_ON_CHILD)

