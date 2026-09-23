--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the device held test (see held.sh).

local device = require("device")

local CONTENT <const> = "held"
local STOP    <const> = "stop"

local held     = {name = "lunatik_held"}
local refused  = {name = "lunatik_refused"}
local selfstop = {name = "lunatik_selfstop"}
local dev, selfdev

function held:read(len, off)
	return CONTENT:sub(off + 1)
end

function held:write(buf)
	if buf == STOP then
		dev:stop()
		dev = nil
		collectgarbage()
	end
end

function refused:open()
	error("refused", 0)
end

function selfstop:open()
	selfdev:stop()
	selfdev = nil
	collectgarbage()
end

dev = device.new(held)
selfdev = device.new(selfstop)
device.new(refused)

