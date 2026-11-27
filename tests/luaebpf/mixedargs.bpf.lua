--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the packet case calling with a packet and a number (see packet.sh).

local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

local function second(_, at)
	return at
end

return xdp.program(function(ctx)
	local p = ctx:packet()
	local a = second(1, 2)
	local b = second(p, 2)
	return a + b
end, {default = action.PASS})

