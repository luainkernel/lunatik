--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the call case that recurses (see call.sh).

local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

local function walk(n)
	if n <= 0 then
		return 0
	end
	local rest = walk(n - 1)
	return rest + n
end

return xdp.program(function(_)
	local v = walk(3)
	return v
end, {default = action.PASS})

