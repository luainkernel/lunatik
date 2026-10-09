--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto seed test (see seed.sh).

local rng  = require("crypto").rng
local test = require("tests.lib").test

local rep = string.rep

local ALG      <const> = "ansi_cprng"
local SEEDSIZE <const> = 48 -- DEFAULT_PRNG_KSZ + 2 * DEFAULT_BLK_SZ, crypto/ansi_cprng.c
local SEED     <const> = rep("v", 16) .. rep("k", 16) .. rep("t", 16) -- V, key and DT, as cprng_reset reads them
local SHORT    <const> = rep("s", 31) -- one byte under DEFAULT_PRNG_KSZ + DEFAULT_BLK_SZ
local BYTES    <const> = 32

test("RNG whose seed size is not 0 is created seeded", function()
	local r, other = rng(ALG), rng(ALG)
	local size = r:seedsize()
	assert(size == SEEDSIZE, ALG .. " should report a seed size of " .. SEEDSIZE .. ", got " .. tostring(size))
	local bytes = r:getbytes(BYTES)
	assert(#bytes == BYTES, "getbytes should return " .. BYTES .. " bytes")
	assert(bytes ~= other:getbytes(BYTES), "two generators created without a seed should give different bytes")
end)

test("RNG whose seed size is not 0 reset without seed", function()
	local r, other = rng(ALG), rng(ALG)
	r:reset(SEED)
	other:reset(SEED)
	local status, err = pcall(r.reset, r)
	assert(status, "rng:reset() should not error: " .. tostring(err))
	other:reset()
	assert(r:getbytes(BYTES) ~= other:getbytes(BYTES), "rng:reset() should replace the seed it had with random bytes")
end)

test("RNG whose seed size is not 0 reset with a seed", function()
	local r, other = rng(ALG), rng(ALG)
	r:reset(SEED)
	other:reset(SEED)
	assert(r:getbytes(BYTES) == other:getbytes(BYTES), "two generators reset with one seed should give the same bytes")
	local status, err = pcall(r.reset, r, SHORT)
	assert(not status and err == "EINVAL", "a short seed should raise EINVAL, got: " .. tostring(err))
	status, err = pcall(r.reset, r, "")
	assert(not status and err == "EINVAL", "an empty seed should raise EINVAL, got: " .. tostring(err))
end)

