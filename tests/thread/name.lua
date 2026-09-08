--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread name test (see name.sh).
--

local lunatik = require("lunatik")
local linux   = require("linux")
local thread  = require("thread")

local BODY <const> = "tests/thread/dummy"
local NAME <const> = "%s%p thread"

return function()
	local t = thread.run(lunatik.runtime(BODY), NAME)
	local comm = t:task():comm()

	t:stop()
	assert(comm == NAME, "the thread name was taken as a format: " .. comm)
	print("thread name: ok")
	while not thread.shouldstop() do
		linux.schedule(100)
	end
end

