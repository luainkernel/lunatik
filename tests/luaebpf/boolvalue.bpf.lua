--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the mapset case writing a boolean (see mapset.sh).

local map = require("bpf.map")
local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

local flows = map.hash("flows", {key = "I4", value = "I4", entries = 4})

return xdp.program(function(_)
	flows[1] = true
	return 0
end, {default = action.PASS})

