--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the device returns test (see returns.sh).

local device = require("device")

local CONTENT <const> = "returns"
local BAD     <const> = "end"
local RAISED  <const> = "raised"

local offset = {name = "lunatik_offset"}
local length = {name = "lunatik_length"}
local raised = {name = "lunatik_raised"}
local sound  = {name = "lunatik_sound"}

function offset:read()
	return CONTENT, BAD
end

function offset:write(buf)
	return #buf, BAD
end

function length:write()
	return BAD
end

function raised:read()
	error(RAISED, 0)
end

function raised:write()
	error(RAISED, 0)
end

function raised:release()
	error(RAISED, 0)
end

function sound:read(len, off)
	local data = CONTENT:sub(off + 1)
	return data, off + #data
end

function sound:write(buf, off)
	return #buf, off + #buf
end

device.new(offset)
device.new(length)
device.new(raised)
device.new(sound)

