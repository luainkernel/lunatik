--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the data load test (see run.sh).

local data = require("data")

local BYTES <const> = "/tmp/lunatik-data/bytes"
local MAX   <const> = 4096

local loaded = data.load(BYTES, MAX) -- the body runs before the runtime is armed, in every context

local function reload()
	assert(#loaded > 0, "the buffer the body loaded lost its bytes")
	data.load(BYTES, MAX)
end

return reload

