--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side kthread body for the shouldstop() spawn context test (see shouldstop.sh).
--

local thread = require("thread")
local linux  = require("linux")

return function()
	while not thread.shouldstop() do
		linux.schedule(10)
	end
	print("shouldstop: ok")
end

