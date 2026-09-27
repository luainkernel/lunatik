--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the hid context test (see context.sh).

local hid = require("hid")

local BUS    <const> = 0x03   -- BUS_USB
local VENDOR <const> = 0xf055 -- no device on the hid bus carries this vendor, so nothing binds

local function register(name)
	hid.register({name = name, id_table = {{bus = BUS, vendor = VENDOR}}})
end

register("lunatik_hid_body")

local function armed()
	register("lunatik_hid_armed")
end

return armed

