--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto acompress test (see run.sh).

local crypto = require("crypto")
local data = require("data")
local lib = require("tests.lib")
local test = lib.test
local closing = require("tests.crypto.closing")

local acompress = crypto.acompress
local char, rep = string.char, string.rep
local concat, insert = table.concat, table.insert

local ALGORITHM <const> = "lz4"
local OUTPUT <const> = 4096
local PAGE <const> = 4096
local SPAN <const> = 3 * PAGE
local PAYLOAD <const> = rep("abcdefghijklmnopqrstuvwxyz", 100)

-- the algorithm the cases allocate, before they run, so run.sh skips the test where the kernel lacks it
lib.alloc(acompress, ALGORITHM)

-- incompressible bytes, so the compression keeps the page spanning of the input
local function noise(length)
	local bytes, seed = {}, 1
	for _ = 1, length do
		seed = (seed * 1103515245 + 12345) % 2147483648
		insert(bytes, char((seed >> 16) % 256))
	end
	return concat(bytes)
end

local SPANNING <const> = noise(SPAN)

local function refused(expected, name, method, ...)
	local ok, err = pcall(method, ...)
	assert(not ok, name .. " should be refused")
	assert(tostring(err):find(expected, 1, true), name .. ": expected '" .. expected .. "', got: " .. tostring(err))
end

local function accepted() end

test("ACOMPRESS compress and decompress round-trip", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	local compressed = req:compress(PAYLOAD, #PAYLOAD * 2)
	assert(type(compressed) == "string", "compressed output should be a string")
	assert(#compressed < #PAYLOAD, "compressed output should be smaller than the input")
	assert(req:decompress(compressed, #PAYLOAD) == PAYLOAD, "round-trip mismatch")
	assert(not req:busy(), "a completed synchronous operation left the request busy")
end)

test("ACOMPRESS decompress into a larger buffer", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	local compressed = req:compress(PAYLOAD, #PAYLOAD * 2)
	assert(req:decompress(compressed, #PAYLOAD + 10) == PAYLOAD, "decompression into a larger buffer failed")
end)

test("ACOMPRESS decompress with too small a buffer raises EINVAL", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	local compressed = req:compress(PAYLOAD, #PAYLOAD * 2)
	refused("EINVAL", "decompress into one byte too few", req.decompress, req, compressed, #PAYLOAD - 1)
end)

test("ACOMPRESS refuses an empty input or a zero length as out of bounds", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	refused("out of bounds", "compress of an empty string", req.compress, req, "", OUTPUT)
	refused("out of bounds", "compress into zero bytes", req.compress, req, PAYLOAD, 0)
	refused("out of bounds", "decompress of an empty string", req.decompress, req, "", OUTPUT)
	refused("out of bounds", "decompress into zero bytes", req.decompress, req, "x", 0)
end)

test("ACOMPRESS refuses an unknown algorithm with ENOENT", function()
	local ok, err = pcall(acompress, "no-such-alg")
	assert(not ok, "acompress accepted an unknown algorithm")
	assert(err == "ENOENT", "Error code should be 'ENOENT', got: " .. tostring(err))
end)

test("ACOMPRESS refuses an object of another class", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	refused("crypto.acompress.request expected, got data", "request:compress", req.compress, data.new(8), "x", 16)
	refused("crypto.acompress expected, got data", "tfm:request", tfm.request, data.new(8))
	local roundtrip = req:decompress(req:compress(PAYLOAD, OUTPUT), #PAYLOAD)
	assert(roundtrip == PAYLOAD, "a refused call left the request unusable")
end)

test("ACOMPRESS data spanning three pages round-trips exactly", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	local compressed = req:compress(SPANNING, SPAN * 2)
	assert(req:decompress(compressed, SPAN) == SPANNING, "round-trip mismatch across pages")
end)

test("ACOMPRESS algname", function()
	local name = acompress(ALGORITHM):algname()
	assert(name == ALGORITHM, "algname should be '" .. ALGORITHM .. "', got: " .. name)
end)

test("ACOMPRESS close releases the transform, and __close is close", function()
	closing.check(acompress(ALGORITHM), "request")
end)

test("ACOMPRESS request close releases the request, and __close is close", function()
	local tfm = acompress(ALGORITHM)
	closing.check(tfm:request(), "busy")
end)

test("ACOMPRESS request keeps its transform alive when the transform is collected", function()
	local req = acompress(ALGORITHM):request()
	collectgarbage()
	collectgarbage()
	local compressed = req:compress(PAYLOAD, #PAYLOAD * 2)
	assert(req:decompress(compressed, #PAYLOAD) == PAYLOAD, "round-trip mismatch after the transform was collected")
end)

test("ACOMPRESS refuses to close a transform with a live request", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	refused("transform has live requests", "tfm close with a live request", tfm.close, tfm)
	req:close()
	tfm:close()
end)

test("ACOMPRESS takes a callback and returns nothing", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	assert(req:compress(PAYLOAD, #PAYLOAD * 2, accepted) == nil, "compress with a callback returned a value")
end)

test("ACOMPRESS refuses a callback that is not a function", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	refused("bad argument #4", "compress with a number callback", req.compress, req, PAYLOAD, OUTPUT, 42)
end)

