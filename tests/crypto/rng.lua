--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
local rng = require("crypto").rng
local test = require"util".test

test("RNG generate 32 bytes", function()
	local r = rng"stdrng"
	assert(r, "Failed to create RNG TFM object")
	local random = r:generate(32)
	assert(type(random) == "string")
	assert(#random == 32)
end)

test("RNG generate 16 bytes with additional input", function()
	local r = rng"stdrng"
	local random = r:generate(16, "additional input")
	assert(type(random) == "string")
	assert(#random == 16)
end)

test("RNG generate 0 bytes (error)", function()
	local r = rng"stdrng"
	local status, err = pcall(r.generate, r, 0)
	assert(not status, "r:generate(0) must return an error")
	assert(err:find"out of bounds", "Error for 0 bytes should indicate 'out of bounds', got: " .. tostring(err))
end)

test("RNG reset without seed", function()
	local r = rng"stdrng"
	local status, err = pcall(r.reset, r)
	assert(status, "rng:reset() should not error: " .. tostring(err))
	local random = r:generate(16)
	assert(type(random) == "string")
	assert(#random == 16)
end)

test("RNG reset with seed", function()
	local r = rng"stdrng"
	local status, err = pcall(r.reset, r, "new_seed_material")
	assert(status, "rng:reset('new_seed_material') should not error: " .. tostring(err))
	local random = r:generate(16)
	assert(#random == 16)
end)

test("RNG additional input or seed that is not a string (error)", function()
	local r = rng"stdrng"
	local status, err = pcall(r.generate, r, 16, {})
	assert(not status, "rng:generate(16, {}) must return an error")
	assert(err:find"string expected", "Error for a table should indicate 'string expected', got: " .. tostring(err))
	status, err = pcall(r.reset, r, {})
	assert(not status, "rng:reset({}) must return an error")
	assert(err:find"string expected", "Error for a table should indicate 'string expected', got: " .. tostring(err))
end)

test("RNG seedsize", function()
	local r = rng"stdrng"
	local size = r:seedsize()
	assert(size == 0, "stdrng is a DRBG, which requires no seed, got a seed size of " .. tostring(size))
end)

test("RNG getbytes 0 bytes (error)", function()
	local r = rng"stdrng"
	local status, err = pcall(r.getbytes, r, 0)
	assert(not status, "rng:getbytes(0) must return an error")
	assert(err:find"out of bounds", "Error for 0 bytes should indicate 'out of bounds', got: " .. tostring(err))
end)

test("RNG getbytes (16 bytes)", function()
	local r = rng"stdrng"
	local bytes16 = r:getbytes(16)
	assert(type(bytes16) == "string", "getbytes(16) should return a string")
	assert(#bytes16 == 16, "getbytes(16) should return 16 bytes")
end)

test("RNG getbytes (32 bytes)", function()
	local r = rng"stdrng"
	local bytes32 = r:getbytes(32)
	assert(type(bytes32) == "string", "getbytes(32) should return a string")
	assert(#bytes32 == 32, "getbytes(32) should return 32 bytes")
end)

test("RNG getbytes (different from previous)", function()
	local r = rng"stdrng"
	local bytes16 = r:getbytes(16)
	local bytes32 = r:getbytes(32)
	assert(bytes16 ~= bytes32, "Consecutive getbytes calls should produce different results (highly probable)")
end)

