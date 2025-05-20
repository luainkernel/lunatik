--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
local new = require"crypto_rng".new

local test, expected, result, random

xpcall(
  function ()
		print"Crypto RNG tests"

    local rng = new"stdrng"

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

		print"All Crypto RNG tests passed"
	end,

	function(msg)
		print("Test " .. test .. " FAILED")
    print("Result:   " .. result)
    print("Expected: " .. expected)
		print(msg)
		print(debug.traceback())
	end
)