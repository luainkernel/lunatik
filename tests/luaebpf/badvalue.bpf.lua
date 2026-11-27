--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the struct case with a value spec of neither kind (see struct.sh).

local map = require("bpf.map")
local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

map.hash("records", {key = "I4", value = {}, entries = 8})

return xdp.program(function(_)
	return 0
end, {default = action.PASS})

