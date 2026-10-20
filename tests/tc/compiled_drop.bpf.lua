--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the tc compiled drop case (see test_tc.sh).

local tc     = require("bpf.tc")
local action = require("linux.tc").action
local packet = require("tests.tc.packet")

return tc.program(function(skb)
	local data = skb:data()
	if packet.isping(data) then
		return action.SHOT
	end
	return action.OK
end, {egress = true, name = "compiled_drop"})

