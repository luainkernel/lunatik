--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the mark case (see mark.sh).

local tc     = require("bpf.tc")
local action = require("linux.tc").action

local PASSED <const> = 2 -- PASSED in mark.sh

local function pass(skb)
	skb:mark(PASSED)
	return action.OK
end

return tc.program(pass, {default = action.OK})

