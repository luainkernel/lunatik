--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto kpp_status test (see kpp_status.sh).

local crypto = require("crypto")
local lib    = require("tests.lib")

local rep    = string.rep
local test   = lib.test
local raises = lib.raises

local ALGORITHM <const> = "lunatik-kpp-status"
local REFUSED   <const> = rep("\1", 32) -- the key kpp_status.c's set_secret answers ECC Fault for
local FAULTY    <const> = rep("\2", 32) -- the key whose public key and secret it answers ECC Fault for

-- nil where the kernel has no CONFIG_CRYPTO_ECDH, which kpp_status.sh skips on
local kpp = crypto.kpp or error("crypto.kpp was not built", 0)

test("KPP constructor raises EIO for a key the engine refuses with its status", function()
	raises("EIO", kpp, ALGORITHM, REFUSED)
end)

test("KPP publickey raises EIO for the status an engine answers", function()
	local ecdh <close> = kpp(ALGORITHM, FAULTY)
	raises("EIO", ecdh.publickey, ecdh)
end)

test("KPP sharedsecret raises EIO for the status an engine completes with", function()
	local ecdh <close> = kpp(ALGORITHM, FAULTY)
	local peer <close> = kpp("ecdh-nist-p256-generic")
	raises("EIO", ecdh.sharedsecret, ecdh, peer:publickey())
end)

