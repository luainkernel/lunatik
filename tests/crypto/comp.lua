--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local comp = require"crypto.comp"
local test = require("util").test

test("COMP compress empty string (error)", function()
	local c = comp.new"lz4"
	local status, err = pcall(c.compress, c, "", 0)
	assert(not status, "Compressing empty string should return an error")
	assert(err:find"out of bounds", "Error should indicate out of bounds, got: " .. tostring(err))
end)

test("COMP decompress empty string (error)", function()
	local c = comp.new"lz4"
	local status, err = pcall(c.decompress, c, "", 0)
	assert(not status, "Decompressing empty string should return an error")
	assert(err:find"out of bounds", "Error should indicate out of bounds, got: " .. tostring(err))
end)

test("COMP compress", function()
	local c = comp.new"lz4"
	local original_data = string.rep("abcdefghijklmnopqrstuvwxyz", 100) .. string.rep("A", 500) .. string.rep("B", 500)
	local compressed = c:compress(original_data, #original_data * 2) -- Allow for some overhead
	assert(type(compressed) == "string", "Compressed output should be a string")
	assert(#compressed < #original_data, "Compressed data should be smaller than original")
end)

test("COMP decompress", function()
	local c = comp.new"lz4"
	local original_data = string.rep("abcdefghijklmnopqrstuvwxyz", 100) .. string.rep("A", 500) .. string.rep("B", 500)
	local compressed = c:compress(original_data, #original_data * 2) -- Allow for some overhead
	local decompressed = c:decompress(compressed, #original_data)
	assert(type(decompressed) == "string", "Decompressed output should be a string")
	assert(decompressed == original_data, "Decompressed data content mismatch")
end)

test("COMP decompress with larger buffer", function()
	local c = comp.new"lz4"
	local original_data = string.rep("abcdefghijklmnopqrstuvwxyz", 100) .. string.rep("A", 500) .. string.rep("B", 500)
	local compressed = c:compress(original_data, #original_data * 2) -- Allow for some overhead
	local decompressed = c:decompress(compressed, #original_data + 10)
	assert(decompressed == original_data, "Decompression with larger buffer failed")
end)

test("COMP decompress with too small buffer (expect error)", function()
	local c = comp.new"lz4"
	local original_data = string.rep("abcdefghijklmnopqrstuvwxyz", 100) .. string.rep("A", 500) .. string.rep("B", 500)
	local compressed = c:compress(original_data, #original_data * 2) -- Allow for some overhead
	local status, err = pcall(c.decompress, c, compressed, #original_data - 1)
	assert(not status, "Decompression with too small buffer should fail")
	assert(err == "EINVAL", "Error code should be 'EINVAL', got: " .. err)
end)

