--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Minimal kthread body used as spawn target in tests.
--

local thread = require("thread")
local linux  = require("linux")

return function()
	while not thread.shouldstop() do
		linux.schedule(100)
	end
end

