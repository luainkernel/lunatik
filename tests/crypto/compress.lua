--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local compress = require("crypto.compress")
local lib = require("tests.lib")
local test = lib.test
local closing = require("tests.crypto.closing")

-- the algorithm the cases allocate, before they run, so run.sh skips the test where the kernel lacks it
lib.alloc(compress.new, "lz4")

local PAYLOAD <const> = string.rep("abcdefghijklmnopqrstuvwxyz", 100) .. string.rep("A", 500) .. string.rep("B", 500)

test("COMPRESS compress empty string (error)", function()
	local c = compress.new("lz4")
	local status, err = pcall(c.compress, c, "", 0)
	assert(not status, "Compressing empty string should return an error")
	assert(err:find("out of bounds"), "Error should indicate out of bounds, got: " .. tostring(err))
end)

test("COMPRESS decompress empty string (error)", function()
	local c = compress.new("lz4")
	local status, err = pcall(c.decompress, c, "", 0)
	assert(not status, "Decompressing empty string should return an error")
	assert(err:find("out of bounds"), "Error should indicate out of bounds, got: " .. tostring(err))
end)

test("COMPRESS refuses an unknown algorithm with ENOENT", function()
	local status, err = pcall(compress.new, "no-such-alg")
	assert(not status, "compress.new accepted an unknown algorithm")
	assert(err == "ENOENT", "Error code should be 'ENOENT', got: " .. tostring(err))
end)

test("COMPRESS compress", function()
	local compressed = compress.new("lz4"):compress(PAYLOAD, #PAYLOAD * 2) -- allow for some overhead
	assert(type(compressed) == "string", "Compressed output should be a string")
	assert(#compressed < #PAYLOAD, "Compressed data should be smaller than original")
end)

test("COMPRESS decompress", function()
	local c = compress.new("lz4")
	local decompressed = c:decompress(c:compress(PAYLOAD, #PAYLOAD * 2), #PAYLOAD)
	assert(type(decompressed) == "string", "Decompressed output should be a string")
	assert(decompressed == PAYLOAD, "Decompressed data content mismatch")
end)

test("COMPRESS decompress with larger buffer", function()
	local c = compress.new("lz4")
	local decompressed = c:decompress(c:compress(PAYLOAD, #PAYLOAD * 2), #PAYLOAD + 10)
	assert(decompressed == PAYLOAD, "Decompression with larger buffer failed")
end)

test("COMPRESS decompress with too small buffer (expect error)", function()
	local c = compress.new("lz4")
	local compressed = c:compress(PAYLOAD, #PAYLOAD * 2)
	local status, err = pcall(c.decompress, c, compressed, #PAYLOAD - 1)
	assert(not status, "Decompression with too small buffer should fail")
	assert(err == "EINVAL", "Error code should be 'EINVAL', got: " .. err)
end)

test("COMPRESS algname", function()
	local name = compress.new("lz4"):algname()
	assert(name == "lz4", "algname should be 'lz4', got: " .. name)
end)

test("COMPRESS close releases the transform, and __close is close", function()
	closing.check(compress.new("lz4"), "compress", "data", 64)
end)

