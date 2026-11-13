--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Hardirq runtime for the crypto hardirq test (see run.sh).

local lunatik = require("lunatik")
local crypto  = require("crypto")
local hex2bin = require("util").hex2bin

local HARDIRQ <const> = "not allowed in a hardirq runtime"
local IRQS    <const> = "not allowed with IRQs disabled"

local TEXT    <const> = "The quick brown fox jumps over the lazy dog"
local DIGEST  <const> = hex2bin("d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")
local KEY     <const> = hex2bin("2b7e151628aed2a6abf7158809cf4f3c")
local COUNTER <const> = hex2bin("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
local PLAIN   <const> = hex2bin("6bc1bee22e409f96e93d7e117393172a")
local CIPHER  <const> = hex2bin("874d6191b620e3261bef6864990db6ce")

local function refused(expected, what, fn, ...)
	local ok, err = pcall(fn, ...)
	assert(not ok, "a hardirq runtime ran " .. what)
	assert(err:find(expected, 1, true), what .. " raised something else: " .. tostring(err))
end

local function construct(when)
	refused(HARDIRQ, "crypto.shash " .. when, crypto.shash, "sha256")
	refused(HARDIRQ, "crypto.skcipher " .. when, crypto.skcipher, "ctr(aes)")
end

construct("in its body")

-- the objects hardirq.lua shares, whose methods the body runs before the runtime is armed, with IRQs on
local function shared(shash, skcipher)
	assert(shash:digest(TEXT) == DIGEST, "a crypto.shash digest in the body differs from shash.lua's")
	skcipher:setkey(KEY)
	assert(skcipher:encrypt(COUNTER, PLAIN) == CIPHER, "a crypto.skcipher encrypt in the body differs from SP 800-38A F.5.1")
end

local env = lunatik._ENV
shared(env["tests/crypto/hardirq.shash"], env["tests/crypto/hardirq.skcipher"])

local function handed(shash, skcipher)
	construct("past its body")
	refused(IRQS, "a crypto.shash method", shash.algname, shash)
	refused(IRQS, "a crypto.skcipher method", skcipher.algname, skcipher)
end

return handed

