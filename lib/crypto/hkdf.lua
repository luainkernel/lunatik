--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- HMAC-based Extract-and-Expand Key Derivation Function (HKDF) based on RFC 5869.
-- This module provides functions to perform HKDF operations, utilizing the
-- underlying `crypto` C module for HMAC calculations. Like every crypto object, an instance is
-- created in a process runtime alone.
-- @classmod crypto.hkdf

local shash = require("crypto").shash
local char, rep, sub = string.char, string.rep, string.sub

--- HKDF operations.
-- This table provides the `new` method to create HKDF instances and also
-- serves as the prototype for these instances.
local hkdf = {}

--- Closes the HKDF instance and releases the underlying HMAC transform.
-- It also runs when a to-be-closed variable holding the instance goes out of scope. Without it, the
-- transform is freed when it is collected.
-- @function hkdf:close
function hkdf:close()
	self.tfm:close()
end

hkdf.__close = hkdf.close
hkdf.__index = hkdf

function hkdf.__len(self)
	return self.tfm:digestsize()
end

--- Creates a new HKDF instance for a given hash algorithm.
-- @function hkdf.new
-- @static
-- @tparam string alg base hash algorithm name (e.g., "sha256", "sha512").
-- The "hmac(" prefix will be added automatically.
-- @treturn hkdf An HKDF instance table with methods for key derivation.
-- @usage local hkdf_sha256 = require("crypto.hkdf").new("sha256")
function hkdf.new(alg)
	local tfm = shash("hmac(" .. alg .. ")")
	return setmetatable({tfm = tfm, salt = rep("\0", tfm:digestsize())}, hkdf)
end

local function hmac(self, key, data)
	self.tfm:setkey(key)
	return self.tfm:digest(data)
end

--- Performs the HKDF Extract step.
-- @function hkdf:extract
-- @tparam[opt] string salt Optional salt value. If nil or not provided, a salt of `hash_len` zeros is used.
-- @tparam string ikm Input Keying Material.
-- @treturn string Pseudorandom Key (PRK).
function hkdf:extract(salt, ikm)
	return hmac(self, (salt or self.salt), ikm)
end

--- Performs the HKDF Expand step.
-- @function hkdf:expand
-- @tparam string prk Pseudorandom Key.
-- @tparam[opt] string info Optional context and application-specific information. Defaults to an empty string if nil.
-- @tparam number length desired length in bytes for the Output Keying Material (OKM), at most 255
--   times the digest size.
-- @treturn string Output Keying Material of the specified `length`.
function hkdf:expand(prk, info, length)
	info = info or ""
	local hash_len = #self
	local n = length / hash_len
	n = (n * hash_len == length) and n or n + 1

	local okm, t = "", ""
	for i = 1, n do
		t = hmac(self, prk, t .. info .. char(i))
		okm = okm .. t
	end
	return sub(okm, 1, length)
end

--- Performs the full HKDF (Extract and Expand) operation.
-- @function hkdf:hkdf
-- @tparam[opt] string salt Optional salt value.
-- @tparam string ikm Input Keying Material.
-- @tparam[opt] string info Optional context and application-specific information.
-- @tparam number length desired length in bytes for the Output Keying Material.
-- @treturn string Output Keying Material.
function hkdf:hkdf(salt, ikm, info, length)
	return self:expand(self:extract(salt, ikm), info, length)
end

return hkdf

