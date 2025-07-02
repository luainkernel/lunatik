--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
local new = require"crypto.rng".new
local test = require"util".test

test("RNG generate 32 bytes", function()
	local rng = new"stdrng"
	assert(rng, "Failed to create RNG TFM object")
	local random = rng:generate(32)
	assert(type(random) == "string")
	assert(#random == 32)
end)

test("RNG generate 0 bytes (error)", function()
	local rng = new"stdrng"
	local status, err = pcall(rng.generate, rng, 0)
	assert(not status, "rng:generate(0) must return an error")
	assert(err:find"out of bounds", "Error for 0 bytes should indicate 'out of bounds', got: " .. tostring(err))
end)

test("RNG reset without seed", function()
	local rng = new"stdrng"
	local status, err = pcall(rng.reset, rng)
	assert(status, "rng:reset() should not error: " .. tostring(err))
	local random = rng:generate(16)
	assert(type(random) == "string")
	assert(#random == 16)
end)

test("RNG reset with seed", function()
	local rng = new"stdrng"
	local status, err = pcall(rng.reset, rng, "new_seed_material")
	assert(status, "rng:reset('new_seed_material') should not error: " .. tostring(err))
	local random = rng:generate(16)
	assert(#random == 16)
end)

test("RNG info", function()
	local rng = new"stdrng"
	local info = rng:info()
	assert(type(info) == "table", "info should return a table")
	assert(type(info.driver_name) == "string", "info.driver_name should be a string")
	assert(type(info.seedsize) == "number", "info.seedsize should be a number")
end)

test("RNG getbytes 0 bytes (error)", function()
	local rng = new"stdrng"
	local status, err = pcall(rng.getbytes, rng, 0)
	assert(not status, "rng:getbytes(0) must return an error")
	assert(err:find"out of bounds", "Error for 0 bytes should indicate 'out of bounds', got: " .. tostring(err))
end)

test("RNG getbytes (16 bytes)", function()
	local rng = new"stdrng"
	local bytes16 = rng:getbytes(16)
	assert(type(bytes16) == "string", "getbytes(16) should return a string")
	assert(#bytes16 == 16, "getbytes(16) should return 16 bytes")
end)

test("RNG getbytes (32 bytes)", function()
	local rng = new"stdrng"
	local bytes32 = rng:getbytes(32)
	assert(type(bytes32) == "string", "getbytes(32) should return a string")
	assert(#bytes32 == 32, "getbytes(32) should return 32 bytes")
end)

test("RNG getbytes (different from previous)", function()
	local rng = new"stdrng"
	local bytes16 = rng:getbytes(16)
	local bytes32 = rng:getbytes(32)
	assert(bytes16 ~= bytes32, "Consecutive getbytes calls should produce different results (highly probable)")
end)

