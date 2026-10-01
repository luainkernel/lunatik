--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto async test (see async.sh).

local crypto = require("crypto")
local test   = require("tests.lib").test

local SKCIPHER <const> = "cryptd(ecb-cipher_null)"
local AEAD     <const> = "cryptd(authenc(digest_null-generic,ecb-cipher_null))"

local function refused(new, algname)
	local ok, err = pcall(new, algname)
	assert(not ok, algname .. " was allocated")
	-- v6.11 and earlier: ENOENT; v6.12 and later: EEXIST
	assert(err == "ENOENT" or err == "EEXIST", "Error code should be 'ENOENT' or 'EEXIST', got: " .. tostring(err))
end

test("skcipher refuses an asynchronous implementation", function()
	refused(crypto.skcipher, SKCIPHER)
end)

test("aead refuses an asynchronous implementation", function()
	refused(crypto.aead, AEAD)
end)

