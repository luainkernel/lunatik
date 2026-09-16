--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the linux.lookup test (see run.sh).
--

local linux = require("linux")

local ABSENT  <const> = "lunatik_no_such_symbol_930"
local PRESENT <const> = "kallsyms_lookup_name"

assert(type(linux.lookup(PRESENT)) == "userdata", "the script body did not resolve " .. PRESENT)

local function lookup()
	assert(type(linux.lookup(PRESENT)) == "userdata", "an armed runtime did not resolve " .. PRESENT)
	assert(linux.lookup(ABSENT) == nil, "an armed runtime found " .. ABSENT)
end

return lookup

