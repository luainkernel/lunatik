--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
local new = require"crypto.rng".new
local util = require("util")
local test = util.test

test("RNG generate 32 bytes", function()
	local rng = new"stdrng"
	assert(rng, "Failed to create RNG TFM object")
	local random = rng:generate(32)
	assert(type(random) == "string")
	assert(#random == 32)
end)

test("RNG generate 0 bytes", function()
	local rng = new"stdrng"
	local random = rng:generate(0)
	assert(random == "", "Expected empty string")
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

test("RNG alg_info", function()
	local rng = new"stdrng"
	local info = rng:alg_info()
	assert(type(info) == "table", "alg_info should return a table")
	assert(type(info.driver_name) == "string", "alg_info.driver_name should be a string")
	assert(type(info.seedsize) == "number", "alg_info.seedsize should be a number")
	-- print("  RNG Driver Name: " .. info.driver_name)
	-- print("  RNG Seed Size: " .. info.seedsize)
end)

test("RNG get_bytes (0 bytes)", function()
	local rng = new"stdrng"
	local bytes0 = rng:get_bytes(0)
	assert(bytes0 == "", "get_bytes(0) should return an empty string")
end)

test("RNG get_bytes (16 bytes)", function()
	local rng = new"stdrng"
	local bytes16 = rng:get_bytes(16)
	assert(type(bytes16) == "string", "get_bytes(16) should return a string")
	assert(#bytes16 == 16, "get_bytes(16) should return 16 bytes")
	-- print("  16 random bytes from get_bytes (hex): " .. bin2hex(bytes16))
end)

test("RNG get_bytes (32 bytes)", function()
	local rng = new"stdrng"
	local bytes32 = rng:get_bytes(32)
	assert(type(bytes32) == "string", "get_bytes(32) should return a string")
	assert(#bytes32 == 32, "get_bytes(32) should return 32 bytes")
end)

test("RNG get_bytes (different from previous)", function()
	local rng = new"stdrng"
	local bytes16 = rng:get_bytes(16)
	local bytes32 = rng:get_bytes(32)
	assert(bytes16 ~= bytes32, "Consecutive get_bytes calls should produce different results (highly probable)")
end)

