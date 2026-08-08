--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread.run class check test (see foreign_object.sh).

local thread  = require("thread")
local linux   = require("linux")
local data    = require("data")
local lunatik = require("lunatik")

local env = lunatik._ENV

return function()
	local ok, err = pcall(thread.run, data.new(8), "foreign_object")
	env.foreign_object = not ok and err:match("runtime expected") ~= nil
	while not thread.shouldstop() do
		linux.schedule(100)
	end
end

