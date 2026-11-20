--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the count case (see count.sh).

local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action
local eth    = require("linux.eth")

local SHARE <const> = 100

-- a stop both callers reach, at the line of its division, under the name of the map the errors
-- count in, which the object keeps for the map
local function luaebpf_errors(n)
	return SHARE // n
end

-- the Ethernet type's low byte, 0 in the frame of the case
local function caller(ctx)
	local p = ctx:packet()
	local n = p:getbyte(eth.HLEN - 1)
	local _ = luaebpf_errors(n)
	return action.PASS
end

xdp.program(function(ctx)
	local p = ctx:packet()
	local first, second = p:getbyte(eth.HLEN), p:getbyte(eth.HLEN + 1)
	local _ = SHARE // first % second
	return action.PASS
end, {name = "lines", default = action.PASS})

xdp.program(caller, {name = "left", default = action.PASS})
xdp.program(caller, {name = "right", default = action.PASS})

