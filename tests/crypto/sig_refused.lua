--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto sig_refused test (see sig_refused.sh).

local crypto = require("crypto")
local lib    = require("tests.lib")
local test   = lib.test

local NAME    <const> = "hmac(sha256)"
local REFUSED <const> = require("tests.crypto.sig_refused_errno")

-- the template the case asks for, before it runs, so sig_refused.sh skips the test where the kernel lacks it
lib.alloc(crypto.shash, NAME)

test("crypto.sig raises " .. REFUSED .. " for " .. NAME .. ", whose template builds no verifier", function()
	local ok, err = pcall(crypto.sig, NAME)
	assert(not ok, "crypto.sig allocated " .. NAME)
	assert(err == REFUSED, "crypto.sig raised " .. tostring(err) .. " where " .. REFUSED .. " was expected")
end)

