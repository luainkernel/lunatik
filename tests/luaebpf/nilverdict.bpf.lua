--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the pass case returning nil (see pass.sh).

local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

xdp.program(function(_)
	return
end, {name = "none", default = action.DROP})

return xdp.program(function(_)
	return nil
end, {name = "explicit", default = action.DROP})

