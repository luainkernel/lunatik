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

-- the objects the case hands over, allocated before it runs, so run.sh skips the test where the kernel lacks one
local shash    = lib.alloc(crypto.shash, "sha256")
local skcipher = lib.alloc(crypto.skcipher, "ctr(aes)")

test("crypto.shash and crypto.skcipher refuse a hardirq runtime, and their methods one handed over there", function()
	local runtime <close> = lunatik.runtime(RECEIVER, "hardirq")
	runtime:resume(shash, skcipher)
end)

