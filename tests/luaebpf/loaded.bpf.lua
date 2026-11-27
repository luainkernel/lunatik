--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the refuse case compiling a loaded chunk (see refuse.sh).

local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

return xdp.program(load("return function(ctx) return 2 end")(), {default = action.PASS})

