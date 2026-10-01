--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Softirq runtime of the hid stop test (see stop.sh).

local drivers = require("tests.hid.drivers")

local function scope(name)
	local held <close> = drivers.register(name)
	local class = getmetatable(held)
	assert(class.__close == class.stop, "a driver's __close is not its stop")
end

local stopped = drivers.register("lunatik_hid_stopped")
stopped:stop()
stopped:stop()

scope("lunatik_hid_closed")

local kept = drivers.register("lunatik_hid_kept")

local function armed()
	kept:stop()
end

return armed

