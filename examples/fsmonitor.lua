--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Logs what changes in one directory: an entry created or deleted, a file
-- written or its attributes changed, with the name, the inode number and the
-- pid of whoever did it.

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local format = string.format

local WATCHED <const> = "/tmp/lunatik-fsmonitor"
local EVENTS  <const> = fs.CREATE | fs.DELETE | fs.MODIFY | fs.ATTRIB

local labels = {
	[fs.CREATE] = "created",
	[fs.DELETE] = "deleted",
	[fs.MODIFY] = "modified",
	[fs.ATTRIB] = "attributes",
}

local function monitor(mask, event)
	local what = labels[mask & EVENTS] or format("%x", mask) -- the mask also carries ISDIR and EVENT_ON_CHILD

	-- the name comes with the event; event:path() would resolve one per call
	print(format("fsmonitor: %s %s ino %s pid %d",
		what, event:name() or "?", event:ino() or "?", event:pid()))
end

local watch = fsnotify.watch(monitor)

-- CREATE and DELETE are the directory's own events; MODIFY and ATTRIB happen on
-- the files inside it and reach this mark only through EVENT_ON_CHILD, which is
-- one level deep: nothing under a subdirectory is reported.
watch:mark(WATCHED, EVENTS | fs.EVENT_ON_CHILD)

