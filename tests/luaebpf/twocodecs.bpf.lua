--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the struct case merging two struct maps (see struct.sh).

local map = require("bpf.map")
local struct = require("struct")
local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

local first = struct{size = 4, fields = {{name = "n", offset = 0, size = 4, signed = false}}}
local second = struct{size = 4, fields = {{name = "m", offset = 0, size = 4, signed = false}}}
local ones = map.hash("ones", {key = "I4", value = first, entries = 8})
local twos = map.hash("twos", {key = "I4", value = second, entries = 8})

return xdp.program(function(ctx)
	local p = ctx:packet()
	local v
	if p:getbyte(0) == 255 then
		local a = ones[1]
		if a then v = a else return 0 end
	else
		local b = twos[1]
		if b then v = b else return 0 end
	end
	return v.n
end, {default = action.PASS})

