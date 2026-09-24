--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the owned test, the devices without a finalizer (see owned.sh).

local device = require("device")

local UNFINALIZED <const> = "lunatik_unfinalized"
local SWAPPED     <const> = "lunatik_swapped"

local unfinalized = device.new{name = UNFINALIZED}
local swapped = device.new{name = SWAPPED}

getmetatable(unfinalized).__gc = nil -- the metatable is the class's: every device of this runtime
debug.setmetatable(swapped, {})

