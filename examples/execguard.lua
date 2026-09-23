--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- An allowlist for exec over one directory: the mark is on that directory's
-- inode, where a mount or superblock mark would deny across a whole filesystem,
-- the programs that undo the rule included.
--
-- A gate, not a sandbox: it fails open, and it decides after the LSMs' open
-- hooks, Landlock's among them, so it can only refuse what they allowed; an
-- LSM that decides the exec later, as AppArmor does, can still refuse it.

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")
local set      = require("set")

local format = string.format

local SCOPE <const> = "/tmp/lunatik-execguard"
local PIDS  <const> = SCOPE .. "/pids"

local allowed = set.new({"true", "false"})

local function readpids(path)
	local file <close> = io.open(path)
	if file == nil then
		return nil
	end

	local listed = {}
	for pid in file:lines("n") do
		listed[pid] = true
	end
	return listed
end

local pids = readpids(PIDS)

local function guard(_, event)
	local name, pid = event:name(), event:pid()

	if allowed:has(name) and (pids == nil or pids[pid]) then
		return fsnotify.action.ALLOW
	end

	print(format("execguard: denied %s to pid %d", name, pid))
	return fsnotify.action.DENY
end

local watch = fsnotify.watch(guard)
watch:mark(SCOPE, fs.OPEN_EXEC_PERM | fs.EVENT_ON_CHILD)

