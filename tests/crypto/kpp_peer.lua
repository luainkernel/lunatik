--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto kpp_peer test (see kpp_peer.sh).

local crypto  = require("crypto")
local refusal = require("tests.crypto.refusal")
local lib     = require("tests.lib")

local rep     = string.rep
local test    = lib.test
local refuses = refusal.check

-- the generic driver, whose computation kpp_peer.sh counts, and the size of a coordinate
local curves <const> = {
	{name = "ecdh-nist-p256-generic", size = 32},
	{name = "ecdh-nist-p384-generic", size = 48},
}

-- nil where the kernel has no CONFIG_CRYPTO_ECDH, which every ECDH provider selects
local kpp = crypto.kpp or error("the kernel serves no " .. curves[1].name, 0)

-- the objects the case allocates, before it runs, so kpp_peer.sh skips the test where the kernel lacks one
for _, curve in ipairs(curves) do
	lib.alloc(kpp, curve.name)
end

test("crypto.kpp refuses a peer's key the curve refuses before the driver computes with it", function()
	for _, curve in ipairs(curves) do
		local ecdh <close> = kpp(curve.name)
		local peer <close> = kpp(curve.name)
		local one = rep("\0", curve.size - 1) .. "\1"
		refuses(ecdh, one .. one) -- (1, 1): off a curve whose b is not 3
		refuses(ecdh, rep("\0", 2 * curve.size)) -- the point at infinity
		refuses(ecdh, rep("\xff", 2 * curve.size)) -- coordinates past the field's prime
		local secret = ecdh:sharedsecret(peer:publickey())
		assert(#secret == curve.size, curve.name .. "'s secret is " .. #secret .. " bytes")
	end
end)

