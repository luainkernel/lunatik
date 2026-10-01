--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the hid context test (see context.sh).

local drivers = require("tests.hid.drivers")

drivers.register("lunatik_hid_body")

local function armed()
	drivers.register("lunatik_hid_armed")
end

return armed

