--
-- SPDX-FileCopyrightText: (c) 2025 Jieming Zhou <qrsikno@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Driver for Qemu's USB mouse with gesture(dragging),
-- swipeing up to lock the mouse and swipeing down to unlock it.

local hid = require("hid")

local driver = {
	name = "gesture",
	id_table = {
		{ vendor = 0x0627, product = 0x0001 }
	}
}

function driver:probe(devid)
	return { x = 0, y = 0, drag = false, lock = false }
end

function driver:raw_event(hdev, state, report, raw_data)
	local btn = raw_data:getbyte(0)
	local dx_byte = raw_data:getbyte(1)
	local dy_byte = raw_data:getbyte(2)
	-- complement conversion
	local dx = dx_byte >= 128 and dx_byte - 256 or dx_byte
	local dy = dy_byte >= 128 and dy_byte - 256 or dy_byte

	local left_down = (btn & 1) == 1
	if left_down then
		state.x = state.x + dx
		state.y = state.y + dy
		state.drag = true
	else
		if state.drag then
			if math.abs(state.x) > 100 or math.abs(state.y) > 100 then
				local direction = ""
				if math.abs(state.x) > math.abs(state.y) then
					direction = state.x > 0 and "rightly" or "leftly"
				else
					direction = state.y > 0 and "downly" or "uply"
				end
				print(string.format("Swipe %s with x=%d, y=%d", direction, state.x, state.y))
				if direction == "uply" then
					state.lock = true
					print("Locking mouse")
				end
				if direction == "downly" and state.lock then
					state.lock = false
					print("Unlocking mouse")
				end
			end
			state.x = 0
			state.y = 0
			state.drag = false
		end
	end
	if state.lock then
		raw_data:setbyte(0, 0) -- buttons
		raw_data:setbyte(1, 0) -- dx
		raw_data:setbyte(2, 0) -- dy
	end
	return false
end

hid.register(driver)

