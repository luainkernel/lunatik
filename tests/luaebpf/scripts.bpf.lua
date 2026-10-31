--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the scripts case (see scripts.sh).

local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

local out = assert(io.open("class.txt", "w"))
out:write(debug.getinfo(require("class"), "S").source, "\n")
out:close()

return xdp.program(function(_)
	return action.PASS
end, {name = "scripts"})

