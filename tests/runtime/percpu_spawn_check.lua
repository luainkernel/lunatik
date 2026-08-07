--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu spawn test (see percpu_spawn.sh).

local lunatik = require("lunatik")
local linux   = require("linux")
local test    = require("util").test

local prefix <const> = "percpu_spawn:"

test("each spawned thread runs on the CPU it is bound to", function()
	local env = lunatik._ENV
	for cpu = 0, linux.numcpus() - 1 do
		local ran = env[prefix .. cpu]
		env[prefix .. cpu] = nil
		assert(ran ~= nil, "no thread ran for CPU " .. cpu)
		assert(ran, "the thread of CPU " .. cpu .. " ran on another CPU")
	end
end)

