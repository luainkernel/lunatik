--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the call case short of an argument (see call.sh).

local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

local function pair(a, b)
	return a + b
end

return xdp.program(function(_)
	local v = pair(1)
	return v
end, {default = action.PASS})

