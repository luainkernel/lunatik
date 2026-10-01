--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Taker script for the module_owner test (see module_owner.sh).

local lunatik = require("lunatik")

local KEY <const> = "tests.runtime.module_owner"

local env = lunatik._ENV
local object = env[KEY]

env[KEY] = nil
assert(object ~= nil, KEY .. " not found in _ENV")
object = nil
collectgarbage()

