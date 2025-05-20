--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
local new = require"crypto.rng".new
local bin2hex = require"util".bin2hex

local test, expected, result, random

xpcall(
  function ()
		print"Crypto RNG tests"
    local rng = new"stdrng"
    assert(rng, "Failed to create RNG TFM object")

    test = "RNG generate 32 bytes"
    random = rng:generate(32)
    expected, result = "string", type(random)
    assert(result == expected)
    expected, result = 32, #random
    assert(result == expected)

    test = "RNG generate 0 bytes"
    random = rng:generate(0)
    expected, result = "", random
    assert(result == expected, "Expected empty string")

    test = "RNG reset without seed"
    expected, result = true, pcall(rng.reset, rng)
    assert(result == expected, "rng:reset() should not error")
    random = rng:generate(16)
    expected, result = "string", type(random)
    assert(result == expected)
    expected, result = 16, #random
    assert(result == expected)

    test = "RNG reset with seed"
    expected, result = true, pcall(rng.reset, rng, "new_seed_material")
    assert(result == expected, "rng:reset('new_seed_material') should not error")
    random = rng:generate(16)
    expected, result = 16, #random
    assert(result == expected)

    test = "RNG alg_info"
    local info = rng:alg_info()
    expected, result = "table", type(info)
    assert(result == expected, "alg_info should return a table")
    expected, result = "string", type(info.driver_name)
    assert(result == expected, "alg_info.driver_name should be a string")
    expected, result = "number", type(info.seedsize)
    assert(result == expected, "alg_info.seedsize should be a number")
    print("  RNG Driver Name: " .. info.driver_name)
    print("  RNG Seed Size: " .. info.seedsize)

    test = "RNG get_bytes (0 bytes)"
    local bytes0 = rng:get_bytes(0)
    expected, result = "", bytes0
    assert(result == expected, "get_bytes(0) should return an empty string")

    test = "RNG get_bytes (16 bytes)"
    local bytes16 = rng:get_bytes(16)
    expected, result = "string", type(bytes16)
    assert(result == expected, "get_bytes(16) should return a string")
    expected, result = 16, #bytes16
    assert(result == expected, "get_bytes(16) should return 16 bytes")
    print("  16 random bytes from get_bytes (hex): " .. bin2hex(bytes16))

    test = "RNG get_bytes (32 bytes)"
    local bytes32 = rng:get_bytes(32)
    expected, result = "string", type(bytes32)
    assert(result == expected, "get_bytes(32) should return a string")
    expected, result = 32, #bytes32
    assert(result == expected, "get_bytes(32) should return 32 bytes")

    test = "RNG get_bytes (different from previous)"
    expected, result = true, bytes16 ~= bytes32
    assert(result == expected, "Consecutive get_bytes calls should produce different results (highly probable)")

		print"All Crypto RNG tests passed"
	end,

	function(msg)
		print("Test " .. test .. " FAILED")
    local res_str = (type(result) == "string" and "hex: " .. bin2hex(result)) or tostring(result)
    local exp_str = (type(expected) == "string" and "hex: " .. bin2hex(expected)) or tostring(expected)
		print("Result:   " .. res_str)
    print("Expected: " .. exp_str)
		print(msg)
		print(debug.traceback())
	end
)