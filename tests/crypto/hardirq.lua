--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto hardirq test (see run.sh).

local lunatik = require("lunatik")
local crypto  = require("crypto")
local lib     = require("tests.lib")
local test    = lib.test

local RECEIVER <const> = "tests/crypto/hardirq_recv"
local SHASH    <const> = "tests/crypto/hardirq.shash"
local SKCIPHER <const> = "tests/crypto/hardirq.skcipher"

-- the objects the case hands over, allocated before it runs, so run.sh skips the test where the kernel lacks one
local shash    = lib.alloc(crypto.shash, "sha256")
local skcipher = lib.alloc(crypto.skcipher, "ctr(aes)")

local env = lunatik._ENV
env[SHASH] = shash
env[SKCIPHER] = skcipher

test("crypto.shash and crypto.skcipher methods run in a hardirq runtime's body, where IRQs are on", function()
	local runtime <close> = lunatik.runtime(RECEIVER, "hardirq")
end)

test("crypto.shash and crypto.skcipher refuse a hardirq runtime, and their methods one handed over there", function()
	local runtime <close> = lunatik.runtime(RECEIVER, "hardirq")
	runtime:resume(shash, skcipher)
end)

env[SHASH] = nil
env[SKCIPHER] = nil

