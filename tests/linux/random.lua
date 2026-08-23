--
-- SPDX-FileCopyrightText: (c) 2026 Harshdeep Singh
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.random test (see run.sh).
--

local linux = require("linux")
local test = require("util").test

test("linux.random(m, n) stays within [m, n]", function()
	for i = 1, 10000 do
		local r = linux.random(32, 126)
		assert(type(r) == "number", "expected number")
		assert(r >= 32 and r <= 126, "out of range: " .. r)
	end
end)

test("linux.random(n) stays within [1, n]", function()
	for i = 1, 1000 do
		local r = linux.random(1000)
		assert(r >= 1 and r <= 1000, "out of range: " .. r)
	end
end)

test("linux.random(m, n) fits string.char for ASCII printable", function()
	for i = 1, 1000 do
		local c = string.char(linux.random(32, 126))
		assert(#c == 1, "expected one character")
	end
end)

