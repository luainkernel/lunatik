local hid = require("luahid") 
local dummy_submitx = function(value)
	-- pass
end
local dummy_submity = function(value)
	-- pass
end
local slow_mouse_driver = {
	name = "Luahid Half-Speed Mouse Example",
	match_list = {
		{ vendor_id = 0x1234, product_id = 0x5678 }, 
	},
	match = function(device) 
		return device.vendor_id == 0x1233
	end,

	report_descriptor = {
		0x05, 0x01, -- Usage Page (Generic Desktop)
		0x09, 0x02, -- Usage (Mouse)
		0xA1, 0x01, -- Collection (Application)
		0x09, 0x01, --   Usage (Pointer)
		0xA1, 0x00, --   Collection (Physical)
		0x05, 0x09, --     Usage Page (Button)
		0x19, 0x01, --     Usage Minimum (Button 1)
		0x29, 0x03, --     Usage Maximum (Button 3)
		0x15, 0x00, --     Logical Minimum (0)
		0x25, 0x01, --     Logical Maximum (1)
		0x95, 0x03, --     Report Count (3)
		0x75, 0x01, --     Report Size (1)
		0x81, 0x02, --     Input (Data,Var,Abs) ; Buttons
		0x95, 0x01, --     Report Count (1)
		0x75, 0x05, --     Report Size (5)
		0x81, 0x03, --     Input (Cnst,Var,Abs) ; Padding
		0x05, 0x01, --     Usage Page (Generic Desktop)
		0x09, 0x30, --     Usage (X)
		0x09, 0x31, --     Usage (Y)
		-- 0x09, 0x38, --     Usage (Wheel) 
		0x15, 0x81, --     Logical Minimum (-127)
		0x25, 0x7F, --     Logical Maximum (127)
		0x75, 0x08, --     Report Size (8)
		0x95, 0x02, --     Report Count (2) ; X, Y
		-- 0x95, 0x03, --     Report Count (3) ; X, Y, Wheel (if wheel is included)
		0x81, 0x06, --     Input (Data,Var,Rel) ; X, Y
		0xC0,       --   End Collection
		0xC0        -- End Collection
	},

	init = function(device)
		if device and device.name then
			print("Initializing Half-Speed Mouse: " .. device.name)
		else
			print("Initializing Half-Speed Mouse with unknown name")
		end
	end,

	on_event = {
		abs = {
			[hid.input.ABS.ABS_X] = function(value)
				-- just ban a negative value
				if value < 0 then
					dummy_submitx(-value)
					return true
				end
				return false  -- returns false to pass the event to the kernel rather than modify/stop it.
			end,
			[hid.input.ABS.ABS_Y] = function(value)
				if value < 0 then
					dummy_submity(-value)
					return true
				end
				return false
			end
		},
	},

	input_mapping = function(event_type, code, value)
		-- map event before sending to kernel input
		-- event_type: such as EV_KEY, EV_REL, EV_ABS
		-- code: suchas input.REL.X, input.REL.Y (for relative mouse)
		-- value: raw value

		local modified_value = value

		if event_type == hid.input.EV.EV_REL then
			if code == hid.input.REL.REL_X then
				modified_value = math.floor(value / 2) -- slow down
			elseif code == hid.input.REL.REL_Y then
				modified_value = math.floor(value / 2) -- slow down
			end
		end

		return event_type, code, modified_value
	end,
}

hid.register(slow_mouse_driver)
