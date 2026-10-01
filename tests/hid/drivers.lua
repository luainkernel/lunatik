--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The driver the hid context and stop scripts register (see context.sh and stop.sh).

local hid = require("hid")

local BUS    <const> = 0x03   -- BUS_USB
local VENDOR <const> = 0xf055 -- no device on the hid bus carries this vendor, so nothing binds

local drivers = {}

function drivers.register(name)
	return hid.register({name = name, id_table = {{bus = BUS, vendor = VENDOR}}})
end

return drivers

