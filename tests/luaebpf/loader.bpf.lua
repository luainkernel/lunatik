--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the loader cases (see load.sh).

local map    = require("bpf.map")
local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

local ENTRIES  <const> = 4
local ETH_HLEN <const> = 14
local SEEN     <const> = 0

local counts = map.array("counts", {key = "I4", value = "I8", entries = ENTRIES})

return xdp.program(function(ctx)
	local packet = ctx:packet()
	if #packet < ETH_HLEN then
		return action.DROP
	end
	counts[SEEN] = #packet
	return action.PASS
end, {name = "loader"})

