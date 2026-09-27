--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Holder for the killable test (see killable.sh): its body holds its runtime's lock, and the
-- lock of one runtime of a percpu set while that runtime's body sleeps.

local lunatik = require("lunatik")

local SET  <const> = "tests/runtime/killable_set"
local KEY  <const> = "killable_set"
local HELD <const> = "killable_held"

local env = lunatik._ENV

local function body()
	env[HELD] = nil
	local set = lunatik.percpu(SET)
	env[KEY] = set
	set:resume()
	env[KEY] = nil
	env[HELD] = nil
	set:stop()
end

return body

