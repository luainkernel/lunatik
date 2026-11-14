--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the nonlinear case (see nonlinear.sh).

local tc     = require("bpf.tc")
local action = require("linux.tc").action

local function open(skb)
	skb:data()
	return action.OK
end

return tc.program(open, {egress = true, default = action.OK, name = "nonlinear"})

