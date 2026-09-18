--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side relay for the stalled destination test (see stall.sh): plain.lua's
-- relay with a send bound long enough that the stop lands inside the send.

local pair   = require("tests.tunnel.pair")
local tunnel = require("tunnel")

-- a stalled pass is this bound in the send and the idle yield after it, so a
-- bound two hundred times the yield puts the stop in the send and not between two
local TIMEOUT <const> = 2000

local listener = pair.listener()

return function()
	local a, b = pair.accept(listener)
	listener:close()
	if a == nil then
		return
	end
	tunnel.body(a, b, {timeout = TIMEOUT})()
	print("tunnel stall: relay ended")
end

