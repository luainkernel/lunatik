--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the count case (see count.sh) that stops nowhere, with no kernel script beside it,
-- whose program and the function it calls are named `luaebpf_errors`, the name the object keeps for
-- the map a stop counts in, though this one declares none.

local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

local function luaebpf_errors(n)
	return n + 1
end

return xdp.program(function(_)
	local _ = luaebpf_errors(1)
	return action.PASS
end, {name = "luaebpf_errors", default = action.PASS})

