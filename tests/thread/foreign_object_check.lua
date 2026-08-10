--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the thread.run class check test (see foreign_object.sh).

local lunatik = require("lunatik")
local test    = require("util").test

local env = lunatik._ENV

test("thread.run refuses an object of another class", function()
	local result = env.foreign_object
	env.foreign_object = nil
	assert(result ~= nil, "the spawned body did not report")
	assert(result == true, "thread.run did not refuse with 'runtime expected'")
end)

