--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the cpu stats test (see run.sh).

local cpu   = require("cpu")
local test  = require("util").test

local refused <const> = {-1, cpu.maxid() + 1, 1 << 32, math.maxinteger, math.mininteger}

local function refuses(id)
	local ok, err = pcall(cpu.stats, id)
	assert(not ok, "cpu.stats accepted " .. id)
	assert(err:match("out of bounds"), "cpu.stats(" .. id .. ") raised something else: " .. err)
end

local function answers(id)
	local stats = cpu.stats(id)
	assert(type(stats.user) == "number", "cpu.stats(" .. id .. ") has no user time")
	assert(type(stats.idle) == "number", "cpu.stats(" .. id .. ") has no idle time")
end

test("cpu.stats answers every online CPU", function()
	for id in cpu.online() do
		answers(id)
	end
end)

test("cpu.stats refuses an id outside the possible ones", function()
	for _, id in ipairs(refused) do
		refuses(id)
	end
end)

