--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.fs test (see run.sh).
--

local fs = require("linux.fs")
local test = require("util").test

-- the FS_* bits are pinned by the FAN_* and IN_* uapi values they line up with
local masks = {
	ACCESS = 0x00000001, MODIFY = 0x00000002, ATTRIB = 0x00000004,
	CLOSE_WRITE = 0x00000008, CLOSE_NOWRITE = 0x00000010, OPEN = 0x00000020,
	MOVED_FROM = 0x00000040, MOVED_TO = 0x00000080, CREATE = 0x00000100,
	DELETE = 0x00000200, DELETE_SELF = 0x00000400, MOVE_SELF = 0x00000800,
	OPEN_EXEC = 0x00001000, UNMOUNT = 0x00002000, Q_OVERFLOW = 0x00004000,
	OPEN_PERM = 0x00010000, ACCESS_PERM = 0x00020000, OPEN_EXEC_PERM = 0x00040000,
	EVENT_ON_CHILD = 0x08000000, ISDIR = 0x40000000,
}

-- absent from the header before 5.16 (ERROR) and 5.17 (RENAME)
local recent = { ERROR = 0x00008000, RENAME = 0x10000000 }

-- composites and private names the include list leaves out
local dropped = { "MOVE", "IN_IGNORED", "DN_MULTISHOT", "EVENTS_POSS_ON_CHILD" }

test("linux.fs carries every event mask at its uapi value", function()
	for name, value in pairs(masks) do
		assert(fs[name] == value, name .. ": " .. tostring(fs[name]))
	end
	for name, value in pairs(recent) do
		assert(fs[name] == nil or fs[name] == value, name .. ": " .. tostring(fs[name]))
	end
end)

test("every linux.fs entry is one bit and no bit repeats", function()
	local bits = 0
	for name, value in pairs(fs) do
		assert(value ~= 0 and value & (value - 1) == 0, name .. " is not a single bit: " .. value)
		assert(bits & value == 0, name .. " repeats a bit: " .. value)
		bits = bits | value
	end
end)

test("linux.fs carries no composite or private name", function()
	for _, name in ipairs(dropped) do
		assert(fs[name] == nil, name .. " is present")
	end
end)

