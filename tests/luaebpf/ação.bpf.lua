--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the bounds case named in UTF-8 (see bounds.sh).

local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

return xdp.program(function(ctx)
	local p = ctx:packet()
	local v = p:getbyte(#p)
	return action.PASS
end, {name = "acao", default = action.PASS})

