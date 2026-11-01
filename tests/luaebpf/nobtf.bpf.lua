--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the nobtf case (see nobtf.sh).

local xdp     = require("bpf.xdp")
local runtime = require("bpf.runtime")
local action  = require("linux.xdp").action

local lua = runtime.new("tests/luaebpf/nobtf")

return xdp.program(function(_)
	local verdict = lua()
	if verdict then
		return verdict
	end
	return action.PASS
end, {name = "nobtf"})

