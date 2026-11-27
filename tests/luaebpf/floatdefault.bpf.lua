--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the refuse case with a float default verdict (see refuse.sh).

local xdp = require("bpf.xdp")

return xdp.program(function(_)
	return 2
end, {default = math.sqrt(4)})

