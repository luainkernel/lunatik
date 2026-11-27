--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the packet case reading two bytes in TC (see packet.sh).

require("luaebpf.emit").unaligned = false
local tc     = require("bpf.tc")
local action = require("linux.tc").action

return tc.program(function(skb)
	local p = skb:data()
	local v = p:getuint16(6)
	return v
end, {default = action.OK})

