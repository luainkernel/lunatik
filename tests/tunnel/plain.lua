--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side relay for the plain tunnel test (see plain.sh).

local pair   = require("tests.tunnel.pair")
local tunnel = require("tunnel")

-- bound in the script body, before the thread is armed: a peer connecting the
-- moment the spawn returns finds the listener already there
local listener = pair.listener()

return function()
	local a, b = pair.accept(listener)
	listener:close()
	if a == nil then
		return
	end
	tunnel.body(a, b)()
	print("tunnel plain: relay ended")
end

