--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel script of the miss case (see miss.sh).

local xdp    = require("xdp")
local action = require("linux.xdp").action

local function callback(_)
	return action.PASS
end

xdp.attach(callback)

