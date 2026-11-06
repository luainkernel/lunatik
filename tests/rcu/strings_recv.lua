--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Receiver sub-script for the rcu.table string values test (see run.sh).

local lunatik = require("lunatik")

local KEY   <const> = "tests.rcu.strings"
local REPLY <const> = "reply"
local HUGE  <const> = 1 << 23

local function check()
	local s = lunatik._ENV[KEY]
	assert(type(s) == "string" and #s == HUGE and not s:find("[^s]"), "an armed runtime read the string short")
end

local function reply()
	check()
	collectgarbage() -- the string read is gone, so the store below puts the entry's last reference
	lunatik._ENV[KEY] = REPLY
end

return reply

