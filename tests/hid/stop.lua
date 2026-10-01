--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the hid stop test (see stop.sh).

local runner = require("lunatik.runner")
local test   = require("tests.lib").test

local DRIVERS <const> = "tests/hid/stop_drivers"
local REFUSAL <const> = "not allowed once the runtime is armed"

-- the runner keeps the drivers' runtime under its name, which the cleanup stops
test("hid: stop is refused once the runtime is armed", function()
	local drivers = runner.run(DRIVERS, "softirq")
	local ok, err = pcall(drivers.resume, drivers)
	assert(not ok, "an armed softirq runtime stopped a driver")
	assert(err:match(REFUSAL), "an armed softirq runtime raised something else: " .. err)
end)

