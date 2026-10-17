--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the set.load test (see run.sh).
--

local set = require("set")

local LIST <const> = "/tmp/lunatik-set/list.set"
local MAX  <const> = 4096

local loaded = set.load(LIST, MAX) -- the body runs before the runtime is armed, in every context

local function reload()
	assert(loaded:has("alpha"), "the set the body loaded lost alpha")
	set.load(LIST, MAX)
end

return reload

