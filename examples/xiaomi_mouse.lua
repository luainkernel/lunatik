--
-- SPDX-FileCopyrightText: (c) 2025 Jieming Zhou <qrsikno@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- ported from kernel src linux/drivers/hid/hid-xiaomi-mouse.c
-- link: https://elixir.bootlin.com/linux/v6.14.7/source/drivers/hid/hid-xiaomi.c
local hid = require("luahid")

local fixed_xiaomi_report_descriptor = {
	0x05, 0x01,         --  Usage Page (Desktop),               --
	0x09, 0x02,         --  Usage (Mouse),                      --
	0xA1, 0x01,         --  Collection (Application),           --
	0x85, 0x03,         --      Report ID (3),                  --
	0x09, 0x01,         --      Usage (Pointer),                --
	0xA1, 0x00,         --      Collection (Physical),          --
	0x05, 0x09,         --          Usage Page (Button),        --
	0x19, 0x01,         --          Usage Minimum (01h),        --
	0x29, 0x05, -- X -- --          Usage Maximum (05h),        --
	0x15, 0x00,         --          Logical Minimum (0),        --
	0x25, 0x01,         --          Logical Maximum (1),        --
	0x75, 0x01,         --          Report Size (1),            --
	0x95, 0x05,         --          Report Count (5),           --
	0x81, 0x02,         --          Input (Variable),           --
	0x75, 0x03,         --          Report Size (3),            --
	0x95, 0x01,         --          Report Count (1),           --
	0x81, 0x01,         --          Input (Constant),           --
	0x05, 0x01,         --          Usage Page (Desktop),       --
	0x09, 0x30,         --          Usage (X),                  --
	0x09, 0x31,         --          Usage (Y),                  --
	0x15, 0x81,         --          Logical Minimum (-127),     --
	0x25, 0x7F,         --          Logical Maximum (127),      --
	0x75, 0x08,         --          Report Size (8),            --
	0x95, 0x02,         --          Report Count (2),           --
	0x81, 0x06,         --          Input (Variable, Relative), --
	0x09, 0x38,         --          Usage (Wheel),              --
	0x15, 0x81,         --          Logical Minimum (-127),     --
	0x25, 0x7F,         --          Logical Maximum (127),      --
	0x75, 0x08,         --          Report Size (8),            --
	0x95, 0x01,         --          Report Count (1),           --
	0x81, 0x06,         --          Input (Variable, Relative), --
	0xC0,               --      End Collection,                 --
	0xC0,               --  End Collection,                     --
	0x06, 0x01, 0xFF,   --  Usage Page (FF01h),                 --
	0x09, 0x01,         --  Usage (01h),                        --
	0xA1, 0x01,         --  Collection (Application),           --
	0x85, 0x05,         --      Report ID (5),                  --
	0x09, 0x05,         --      Usage (05h),                    --
	0x15, 0x00,         --      Logical Minimum (0),            --
	0x26, 0xFF, 0x00,   --      Logical Maximum (255),          --
	0x75, 0x08,         --      Report Size (8),                --
	0x95, 0x04,         --      Report Count (4),               --
	0xB1, 0x02,         --      Feature (Variable),             --
	0xC0                --  End Collection                      --
}

local xiaomi_mouse_driver = {
	name = "luahid_xiaomi_mouse_driver",
	match_list = {
		{ vendor_id = 0x2717, product_id = 0x5014 },	-- copied from kernel src linux/drivers/hid/hid-xiaomi.c, at 80th lines
														-- link: https://elixir.bootlin.com/linux/v6.14.7/source/drivers/hid/hid-xiaomi.c
	},

	report_descriptor = fixed_xiaomi_report_descriptor
}

hid.register(xiaomi_mouse_driver)
