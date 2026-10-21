--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the pass case (see pass.sh).

local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

xdp.program(function(_)
	return action.PASS
end, {name = "pass"})

return xdp.program(function(_)
	return action.DROP
end, {name = "drop", default = action.ABORTED})

