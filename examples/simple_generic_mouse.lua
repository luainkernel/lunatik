--
-- SPDX-FileCopyrightText: (c) 2025 Jieming Zhou <qrsikno@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- example of a simple generic mouse driver
local hid = require("luahid")

local mouse_driver = {
	name = "luahid_simple_generic_mouse_driver",
}

hid.register(mouse_driver)
