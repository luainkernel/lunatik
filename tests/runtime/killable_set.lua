--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Percpu script for the killable test (see killable.sh): the first runtime resumed sleeps
-- under its lock.

local lunatik = require("lunatik")
local linux   = require("linux")

local HELD   <const> = "killable_held"
local HOLD   <const> = 10000
local PREFIX <const> = "killable test: "

local env = lunatik._ENV

local function body()
	if not env[HELD] then
		env[HELD] = true
		print(PREFIX .. "held")
		linux.schedule(HOLD)
	end
end

return body

