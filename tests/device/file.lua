--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the device file test (see file.sh).

local device = require("device")

local SEP <const> = ","

local files  = {name = "lunatik_files"}
local closed = {name = "lunatik_closed"}
local opened = 0
local released = {}

function files:open(file)
	opened = opened + 1
	file.id = opened
end

function files:write(buf, off, file)
	file.data = buf
end

function files:read(len, off, file)
	local data = file.data or ""
	file.data = nil
	return data
end

function files:release(file)
	table.insert(released, file.id)
end

function closed:read(len, off)
	return table.concat(released, SEP):sub(off + 1)
end

device.new(files)
device.new(closed)

