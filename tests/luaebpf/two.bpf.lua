--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of two XDP programs, which one device cannot both take (see undo.sh).

local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

xdp.program(function(_)
	return action.PASS
end, {name = "first"})

return xdp.program(function(_)
	return action.PASS
end, {name = "second"})

