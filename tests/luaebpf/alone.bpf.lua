--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file with no kernel script beside it (see load.sh).

local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

return xdp.program(function(_)
	return action.PASS
end, {name = "alone"})

