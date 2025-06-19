--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local new = require"crypto.comp".new
local bin2hex = require"util".bin2hex

local test, expected, result, compressed, decompressed

xpcall(
  function ()
		print"Crypto COMP tests"

    -- Note: "lz4" is a common compression algorithm available in the kernel.
    -- Availability depends on kernel configuration.
    local comp = new"lz4"

    test = "COMP compress empty string"
    -- Need to provide max output size for compress (can be 0 for empty input)
    expected, result = "", comp:compress("", 0)
    assert(result == expected, "Compressing empty string should return empty string")

    test = "COMP decompress empty string"
    expected, result = "", comp:decompress("", 100) -- Max length doesn't matter for empty input
    assert(result == expected, "Decompressing empty string should return empty string")

    local original_data = string.rep("abcdefghijklmnopqrstuvwxyz", 100) .. string.rep("A", 500) .. string.rep("B", 500)
    local original_len = #original_data

    test = "COMP compress"
    -- Need to provide max output size for compress
    compressed = comp:compress(original_data, original_len * 2) -- Allow for some overhead
    expected, result = "string", type(compressed)
    assert(result == expected, "Compressed output should be a string")
    expected, result = true, #compressed < original_len
    assert(result == expected, "Compressed data should be smaller than original")

    test = "COMP decompress"
    -- For decompression, we need to provide the maximum possible output size.
    -- In this test, we know the original size, so we use that.
    decompressed = comp:decompress(compressed, original_len)
    expected, result = "string", type(decompressed)
    assert(result == expected, "Decompressed output should be a string")
    expected, result = original_len, #decompressed
    assert(result == expected, "Decompressed data length mismatch")
    expected, result = original_data, decompressed
    assert(result == expected, "Decompressed data content mismatch")

    -- Test decompression with slightly larger buffer
    test = "COMP decompress with larger buffer"
    expected, result = original_data, comp:decompress(compressed, original_len + 10)
    assert(result == expected, "Decompression with larger buffer failed")

    -- Test decompression with too small buffer (should error)
    test = "COMP decompress with too small buffer (expect error)"
    local success, err = pcall(comp.decompress, comp, compressed, original_len - 1)
    expected, result = false, success
    assert(result == expected, "Decompression with too small buffer should fail")
    -- Check if the error message indicates buffer size or crypto error
    expected, result = true, not not (string.find(err, "failed") or string.find(err, "buffer too small") or string.find(err, "data corrupted"))
    assert(result == expected, "Error message for small buffer is not as expected: " .. err)

		print"All Crypto COMP tests passed"
	end,

	function(msg)
		print("Test " .. test .. " FAILED")
    -- Attempt to print result/expected if they are strings, otherwise print type
    -- Use concise notation with 'and'/'or' and bin2hex for strings
    local res_str = (type(result) == "string" and "hex: " .. bin2hex(result)) or tostring(result)
    local exp_str = (type(expected) == "string" and "hex: " .. bin2hex(expected)) or tostring(expected)
		print("Result:   " .. res_str)
    print("Expected: " .. exp_str)
		print(msg)
		print(debug.traceback())
	end
)

