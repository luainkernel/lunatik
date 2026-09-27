--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the linux.netns test (see run.sh).
--

local linux = require("linux")

local INIT <const> = 1 -- pid 1 lives in the initial namespace, so its netns is linux.netns()

local function netns()
	local ok, home = pcall(linux.netns)
	assert(ok, "linux.netns refused the initial namespace, which takes no pid")
	assert(linux.netns(INIT) == home, "pid 1 is not in the initial namespace")
end

netns()

return netns

