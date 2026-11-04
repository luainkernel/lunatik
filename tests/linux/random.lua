--
-- SPDX-FileCopyrightText: (c) 2026 Harshdeep Singh
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.random test (see run.sh).
--

local linux = require("linux")
local test = require("tests.lib").test

test("linux.random(m, n) stays within [m, n]", function()
	for _ = 1, 10000 do
		local r = linux.random(32, 126)
		assert(type(r) == "number", "expected number")
		assert(r >= 32 and r <= 126, "out of range: " .. r)
	end
end)

test("linux.random(n) stays within [1, n]", function()
	for _ = 1, 1000 do
		local r = linux.random(1000)
		assert(r >= 1 and r <= 1000, "out of range: " .. r)
	end
end)

test("linux.random(m, n) stays within a negative range", function()
	for _ = 1, 1000 do
		local r = linux.random(-126, -32)
		assert(r >= -126 and r <= -32, "out of range: " .. r)
	end
end)

test("linux.random(m, n) answers m when m == n and stays within the widest interval", function()
	assert(linux.random(5, 5) == 5, "linux.random(5, 5) is not 5")
	for _ = 1, 1000 do
		assert(linux.random(0, math.maxinteger) >= 0, "out of [0, math.maxinteger]")
	end
end)

test("linux.random(m, n) is uniform over a range that does not divide 2^64", function()
	local up, half, draws, below = (3 << 61) - 1, 1 << 62, 10000, 0
	for _ = 1, draws do
		if linux.random(0, up) < half then
			below = below + 1
		end
	end
	local uniform, modulo = draws * 2 // 3, draws * 3 // 4
	assert(math.abs(below - uniform) < math.abs(below - modulo),
		below .. " of " .. draws .. " draws below 2^62, " .. uniform .. " when uniform")
end)

