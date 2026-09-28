--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the cpu ids test (see run.sh).

local cpu  = require("cpu")
local test = require("util").test

local counts <const> = {possible = cpu.num_possible, present = cpu.num_present, online = cpu.num_online}
local refused <const> = {-2, cpu.maxid() + 1, 1 << 32, math.maxinteger, math.mininteger}

local function walk(mask)
	local count, last = 0, nil
	for id in cpu[mask]() do
		assert(last == nil or id > last, "cpu." .. mask .. "() yielded " .. id .. " after " .. tostring(last))
		count, last = count + 1, id
	end
	return count, last
end

local function refuses(mask)
	local step = cpu[mask]()
	for _, id in ipairs(refused) do
		local ok, err = pcall(step, nil, id)
		assert(not ok, "cpu." .. mask .. "()'s step accepted " .. id)
		assert(err:match("out of bounds"),
			"cpu." .. mask .. "()'s step given " .. id .. " raised something else: " .. err)
	end
end

test("each iterator yields its CPUs in ascending order, as many as its count", function()
	for mask, count in pairs(counts) do
		local yielded, expected = walk(mask), count()
		assert(yielded == expected, "cpu." .. mask .. "() yielded " .. yielded .. " ids, its count is " .. expected)
	end
end)

test("maxid is the last possible CPU", function()
	local _, last = walk("possible")
	local maxid = cpu.maxid()
	assert(last == maxid, "the last possible CPU is " .. last .. ", cpu.maxid() is " .. maxid)
end)

test("each iterator's step refuses an id outside the possible ones", function()
	for mask in pairs(counts) do
		refuses(mask)
	end
end)

