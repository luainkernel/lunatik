--
-- SPDX-FileCopyrightText: (c) 2025-2026 Jieming Zhou <qrsikno@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Driver for QEMU's USB mouse with gesture (dragging),
-- swiping right to lock the mouse and swiping left to unlock it.

local hid = require("hid")

local driver = {name = "gesture", id_table = {{vendor = 0x0627, product = 0x0001}}}

local threshold = 2

local function debug(fmt, ...)
	print(string.format(fmt, ...))
end

function driver:probe(id)
	self.state = {x = 0, count = 0, lock = false}
end

local function forward(x0, x1)
	return (x0 >= 32767 and x1 <= 0) or (x1 > x0)
end

local function count(state, direction)
	if direction ~= "neutral" then
		if state.direction == direction then
			state.count = state.count + 1
		else
			state.count = 0
			state.direction = direction
		end
	end
	return state.count
end

function driver:raw_event(hdev, report, raw)
	local state = self.state
	local button = raw:getbyte(0)

	local left_down = (button & 1) == 1
	if left_down then
		local x0 = state.x
		local x1 = raw:getint16(1)
		local direction = x0 == x1 and "neutral" or
			forward(x0, x1) and "right" or "left"

		debug("%s\t%d %d", direction, x0, x1)
		if count(state, direction) > threshold then
			if direction == "right" then
				state.lock = true
			elseif direction == "left" then
				state.lock = false
			end
		end
		state.x = x1
	end

	if state.lock then
		local last = #raw - 1
		for i = 0, last do 
			raw:setbyte(i, 0)
		end
	end
end

hid.register(driver)

