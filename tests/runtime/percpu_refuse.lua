--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu refusal test (see percpu_refuse.sh).

local device = require("device")
local stat   = require("linux.stat")

local driver = {name = "percpu_refuse", mode = stat.IRUGO}

function driver:read()
	return ""
end

device.new(driver)

