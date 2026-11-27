--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the call case with five arguments (see call.sh).

local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

local function five(a, b, c, d, e)
	return a + b + c + d + e
end

return xdp.program(function(_)
	local v = five(1, 2, 3, 4, 5)
	return v
end, {default = action.PASS})

