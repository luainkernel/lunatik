--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file with no kernel script beside it, whose errors `lunatik bpf --errors` reports (see
-- count.sh).

local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action
local eth    = require("linux.eth")

local SHARE <const> = 100

return xdp.program(function(ctx)
	local p = ctx:packet()
	local kind = p:getbyte(eth.HLEN)
	-- a place no frame stops at: the compiler tests the divisor it cannot hold, which is never 0
	local _ = SHARE // (kind | 1)
	return action.PASS
end, {name = "stopper", default = action.PASS})

