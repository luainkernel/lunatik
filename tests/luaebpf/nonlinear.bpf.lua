--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the nonlinear case (see nonlinear.sh).

local tc     = require("bpf.tc")
local action = require("linux.tc").action

local PAYLOAD <const> = 1024 -- PAYLOAD in nonlinear.sh
local FILL    <const> = 0x58 -- FILL in nonlinear.sh, 'X', the byte of the payload the program drops

local function drop(skb)
	if #skb < PAYLOAD then
		return action.OK
	end
	local p = skb:data()
	if #p == #skb and p:getbyte(#p - 1) == FILL then
		return action.SHOT
	end
	return action.OK
end

return tc.program(drop, {egress = true, default = action.OK, name = "nonlinear"})

