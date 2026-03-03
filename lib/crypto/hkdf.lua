--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- HMAC-based Extract-and-Expand Key Derivation Function (HKDF) based on RFC 5869.
-- This module provides functions to perform HKDF operations, utilizing the
-- underlying `crypto_shash` C module for HMAC calculations.
-- @classmod crypto.hkdf

local shash = require("crypto.shash")
local char, rep, sub = string.char, string.rep, string.sub

--- HKDF operations.
-- This table provides the `new` method to create HKDF instances and also
-- serves as the prototype for these instances.
local HKDF = {}

--- Closes the HKDF instance and releases the underlying HMAC transform.
-- This method is also called by the garbage collector.
-- @function HKDF:close
function HKDF:close()
	if self.tfm then
		self.tfm:__close()
		self.tfm = nil
	end
end

HKDF.__close = HKDF.close
HKDF.__index = HKDF

function HKDF.__len(self)
	return self.tfm:digestsize()
end

--- Creates a new HKDF instance for a given hash algorithm.
-- @function HKDF.new
-- @tparam string alg The base hash algorithm name (e.g., "sha256", "sha512").
-- The "hmac(" prefix will be added automatically.
-- @treturn HKDF An HKDF instance table with methods for key derivation.
-- @usage local hkdf_sha256 = require("crypto.hkdf").new("sha256")
function HKDF.new(alg)
	local hmac = setmetatable({}, HKDF)
	hmac.tfm = shash.new("hmac(" .. alg .. ")")
	hmac.salt = rep("\0", #hmac)

	return hmac
end

--- Performs an HMAC calculation using the instance's algorithm.
-- @tparam string key The HMAC key.
-- @tparam string data The data to hash.
-- @treturn string The HMAC digest.
function HKDF:hmac(key, data)
	self.tfm:setkey(key)
	return self.tfm:digest(data)
end

--- Performs the HKDF Extract step.
-- @function HKDF:extract
-- @tparam[opt] string salt Optional salt value. If nil or not provided, a salt of `hash_len` zeros is used.
-- @tparam string ikm Input Keying Material.
-- @treturn string The Pseudorandom Key (PRK).
function HKDF:extract(salt, ikm)
	return self:hmac((salt or self.salt), ikm)
end

--- Performs the HKDF Expand step.
-- @function HKDF:expand
-- @tparam string prk Pseudorandom Key.
-- @tparam[opt] string info Optional context and application-specific information. Defaults to an empty string if nil.
-- @tparam number length The desired length in bytes for the Output Keying Material (OKM).
-- @treturn string The Output Keying Material of the specified `length`.
function HKDF:expand(prk, info, length)
	info = info or ""
	local hash_len = #self
	local n = length / hash_len
	n = (n * hash_len == length) and n or n + 1

	local okm, t = "", ""
	for i = 1, n do
		t = self:hmac(prk, t .. info .. char(i))
		okm = okm .. t
	end
	return sub(okm, 1, length)
end

--- Performs the full HKDF (Extract and Expand) operation.
-- @function HKDF:hkdf
-- @tparam[opt] string salt Optional salt value.
-- @tparam string ikm Input Keying Material.
-- @tparam[opt] string info Optional context and application-specific information.
-- @tparam number length The desired length in bytes for the Output Keying Material.
-- @treturn string The Output Keying Material.
function HKDF:hkdf(salt, ikm, info, length)
	return self:expand(self:extract(salt, ikm), info, length)
end

return HKDF

