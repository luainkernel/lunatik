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
local rep = string.rep

local ALGORITHM <const> = "lz4"
local OUTPUT <const> = 4096
local PAYLOAD <const> = rep("abcdefghijklmnopqrstuvwxyz", 100)

-- the algorithm the cases allocate, before they run, so run.sh skips the test where the kernel lacks it
lib.alloc(acompress, ALGORITHM)

local function refused(expected, name, method, ...)
	local ok, err = pcall(method, ...)
	assert(not ok, name .. " should be refused")
	assert(tostring(err):find(expected, 1, true), name .. ": expected '" .. expected .. "', got: " .. tostring(err))
end

local function accepted() end

test("ACOMPRESS refuses an empty input or a zero length as out of bounds", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	refused("out of bounds", "compress of an empty string", req.compress, req, "", OUTPUT, accepted)
	refused("out of bounds", "compress into zero bytes", req.compress, req, PAYLOAD, 0, accepted)
	refused("out of bounds", "decompress of an empty string", req.decompress, req, "", OUTPUT, accepted)
	refused("out of bounds", "decompress into zero bytes", req.decompress, req, "x", 0, accepted)
end)

test("ACOMPRESS refuses an unknown algorithm with ENOENT", function()
	local ok, err = pcall(acompress, "no-such-alg")
	assert(not ok, "acompress accepted an unknown algorithm")
	assert(err == "ENOENT", "Error code should be 'ENOENT', got: " .. tostring(err))
end)

test("ACOMPRESS refuses an object of another class", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	refused("crypto.acompress.request expected, got data", "request:compress", req.compress, data.new(8), "x",
		16, accepted)
	refused("crypto.acompress expected, got data", "tfm:request", tfm.request, data.new(8))
	local ok, err = pcall(req.compress, req, PAYLOAD, OUTPUT, accepted)
	assert(ok, "a refused call left the request unusable: " .. tostring(err))
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
	local ok, err = pcall(req.compress, req, PAYLOAD, OUTPUT, accepted)
	assert(ok, "a submission after the transform was collected failed: " .. tostring(err))
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
	-- one request each: an asynchronous driver keeps the first busy
	assert(select("#", tfm:request():compress(PAYLOAD, OUTPUT, accepted)) == 0, "compress returned a value")
	assert(select("#", tfm:request():decompress("x", OUTPUT, accepted)) == 0, "decompress returned a value")
end)

test("ACOMPRESS refuses a callback that is not a function", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	refused("bad argument #4", "compress with a number callback", req.compress, req, PAYLOAD, OUTPUT, 42)
end)

test("ACOMPRESS refuses a submission without a callback", function()
	local tfm = acompress(ALGORITHM)
	local req = tfm:request()
	refused("bad argument #4", "compress without a callback", req.compress, req, PAYLOAD, OUTPUT)
	refused("bad argument #4", "decompress without a callback", req.decompress, req, "x", OUTPUT)
end)

