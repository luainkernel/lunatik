--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the mapget case merging two maps (see mapget.sh).

local map = require("bpf.map")
local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

local wide = map.hash("wide", {key = "I4", value = "I8", entries = 8})
local thin = map.hash("thin", {key = "I4", value = "I1", entries = 8})

return xdp.program(function(ctx)
	local p = ctx:packet()
	local v
	if p:getbyte(0) == 255 then
		v = wide[1]
	else
		v = thin[1]
	end
	if v then
		return v
	end
	return 0
end, {default = action.PASS})

