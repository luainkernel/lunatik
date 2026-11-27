--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the forvar case whose step is zero (see forvar.sh).

local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

return xdp.program(function(_)
	local s = 0
	for i = 1, 10, 0 do
		s = s + i
	end
	return s
end, {default = action.PASS})

