--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the device returns test (see returns.sh).

local device = require("device")
local errno  = require("linux.errno")

local CONTENT <const> = "returns"
local BAD     <const> = "end"
local RAISED  <const> = "raised"

local SEP         <const> = ","
local SHORT       <const> = 1
local MAX_ERRNO   <const> = 4095 -- include/linux/err.h
local EIOCBQUEUED <const> = 529  -- include/linux/errno.h, kept from user programs

local offset = {name = "lunatik_offset"}
local length = {name = "lunatik_length"}
local raised = {name = "lunatik_raised"}
local sound  = {name = "lunatik_sound"}

local refusing  = {name = "lunatik_refusing"}
local failing   = {name = "lunatik_failing"}
local ended     = {name = "lunatik_ended"}
local unnegated = {name = "lunatik_unnegated"}
local notnumber = {name = "lunatik_notnumber"}
local invalid   = {name = "lunatik_invalid"}
local internal  = {name = "lunatik_internal"}
local short     = {name = "lunatik_short"}
local written   = {}

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

function sound:read(_, off)
	local data = CONTENT:sub(off + 1)
	return data, off + #data
end

function sound:write(buf, off)
	return #buf, off + #buf
end

function refusing:open()
	return -errno.EBUSY
end

function failing:open()
	return 0
end

function failing:read()
	return -errno.EAGAIN
end

function failing:write()
	return -errno.ENOSPC
end

function ended:read()
	return 0
end

function unnegated:open()
	return errno.EBUSY
end

function notnumber:open()
	return true
end

function invalid:read()
	return errno.EAGAIN
end

function invalid:write()
	return -(MAX_ERRNO + 1)
end

function internal:read()
	return -EIOCBQUEUED
end

function short:write(buf)
	table.insert(written, buf)
	return SHORT
end

function short:read(_, off)
	return table.concat(written, SEP):sub(off + 1)
end

device.new(offset)
device.new(length)
device.new(raised)
device.new(sound)
device.new(refusing)
device.new(failing)
device.new(ended)
device.new(unnegated)
device.new(notnumber)
device.new(invalid)
device.new(internal)
device.new(short)

