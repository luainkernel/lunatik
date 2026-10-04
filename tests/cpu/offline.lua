--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the cpu offline test (see run.sh).

local cpu  = require("cpu")
local test = require("tests.lib").test

test("cpu.stats answers nil for a possible CPU that is not online", function()
	local online = {}
	for id in cpu.online() do
		online[id] = true
	end
	for id in cpu.possible() do
		if not online[id] then
			assert(cpu.stats(id) == nil, "cpu.stats(" .. id .. ") answered an offline CPU")
		end
	end
end)

