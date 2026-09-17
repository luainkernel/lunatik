--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Atomic-context body for the data zeroing test (see run.sh).

local zeroing = require("tests.data.zeroing")

local PAGE   <const> = 4096
local BLOCK  <const> = 64
local ROUNDS <const> = 4

return function()
	zeroing.newrounds(ROUNDS, BLOCK)
	zeroing.checkregrow(PAGE * 2, BLOCK) -- past a page, which GFP_ATOMIC alone keeps on krealloc
end

