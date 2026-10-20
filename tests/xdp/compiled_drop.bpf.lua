--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the xdp compiled drop case (see test_xdp.sh).

local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action
local packet = require("tests.xdp.packet")

return xdp.program(function(ctx)
	local data = ctx:packet()
	if packet.isping(data) then
		return action.DROP
	end
	return action.PASS
end, {name = "compiled_drop"})

