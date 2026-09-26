--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the linux.schedule test (see run.sh).
--

local linux = require("linux")

local NAP_MS  <const> = 1
local REFUSAL <const> = "not allowed after module load"

assert(linux.schedule(NAP_MS) == 0, "the script body, which runs in process context, could not sleep")

local function schedule()
	local ok, err = pcall(linux.schedule, NAP_MS)
	assert(not ok, "an armed runtime slept")
	assert(err:match(REFUSAL), "an armed runtime raised something else: " .. err)
end

return schedule

