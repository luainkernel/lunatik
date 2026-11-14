--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the nobtf case (see nobtf.sh).

local xdp     = require("bpf.xdp")
local lunatik = require("lunatik")
local action  = require("linux.xdp").action

local absent = lunatik.runtime("tests/luaebpf/absent")

return xdp.program(function(_)
	local verdict = absent:run()
	if verdict then
		return verdict
	end
	return action.PASS
end, {name = "nobtf"})

