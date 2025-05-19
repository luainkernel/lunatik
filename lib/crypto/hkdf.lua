--- HMAC-based Extract-and-Expand Key Derivation Function (HKDF) based on RFC 5869.
-- This module provides functions to perform HKDF operations, utilizing the
-- underlying `crypto_shash` C module for HMAC calculations.
--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- @module crypto.hkdf

local shash = require("crypto_shash")
local char, sp, rep, sub = string.char, string.pack, string.rep, string.sub

--- HKDF instance methods.
-- This table represents an HKDF instance configured for a specific hash algorithm.
-- It is created by calling the main function of the `crypto.hkdf` module.
-- @type HKDFInstance
-- @field hkdf Perform the full HKDF (extract and expand).
-- @field extract Perform the HKDF extract step.
-- @field expand Perform the HKDF expand step.
-- @field tls13_expand_label Perform TLS 1.3 HKDF-Expand-Label.
-- @field close Release resources associated with this HKDF instance.

--- Creates a new HKDF instance for a given hash algorithm.
-- @tparam string alg The base hash algorithm name (e.g., "sha256", "sha512").
-- The "hmac(" prefix will be added automatically.
-- @treturn HKDFInstance An HKDF instance table with methods for key derivation.
-- @usage local hkdf_sha256 = require("crypto.hkdf")("sha256")
return function (alg)
	alg = "hmac(" .. alg .. ")"
	local hmac_tfm = shash.new(alg)
	local hash_len = hmac_tfm:digestsize()  -- The digestsize of "hmac(alg)" is the same as "alg"
	local default_salt = rep("\0", hash_len)  -- default salt is zeros

	local function hmac(key, data)
		-- The key needs to be set before each HMAC operation if it changes,
		-- or if the TFM is used for other operations in between.
		-- For HKDF, the PRK is used as the key for multiple HMAC operations in expand.
		hmac_tfm:setkey(key)
		return hmac_tfm:digest(data) -- 'digest' is now a direct method of the TFM object
	end

	--- Performs the HKDF Extract step.
	-- @function extract
	-- @within HKDFInstance
	-- @tparam[opt] string salt Optional salt value. If nil or not provided, a salt of `hash_len` zeros is used.
	-- @tparam string ikm Input Keying Material.
	-- @treturn string The Pseudorandom Key (PRK).
	local function extract(salt, ikm)
		return hmac((salt or default_salt), ikm)
	end

	--- Performs the HKDF Expand step.
	-- @function expand
	-- @within HKDFInstance
	-- @tparam string prk Pseudorandom Key (typically the output of the extract step).
	-- @tparam[opt] string info Optional context and application-specific information. Defaults to an empty string if nil.
	-- @tparam number length The desired length in bytes for the Output Keying Material (OKM).
	-- @treturn string The Output Keying Material of the specified `length`.
	local function expand(prk, info, length)
		info = info or ""
		local n = length / hash_len  -- integer division, as we’re in Lunatik
		n = (n * hash_len == length) and n or n + 1
		if length == 0 then n = 0 end

		local okm, t = "", ""
		for i = 1, n do
			t = hmac(prk, t .. info .. char(i))
			okm = okm .. t
		end
		return sub(okm, 1, length)
	end

	--- Performs the full HKDF (Extract and Expand) operation.
	-- @function hkdf
	-- @within HKDFInstance
	-- @tparam[opt] string salt Optional salt value.
	-- @tparam string ikm Input Keying Material.
	-- @tparam[opt] string info Optional context and application-specific information.
	-- @tparam number length The desired length in bytes for the Output Keying Material.
	-- @treturn string The Output Keying Material.
	local function hkdf(salt, ikm, info, length)
		return expand(extract(salt, ikm), info, length)
	end

	--- Derives a key using HKDF-Expand-Label as defined in RFC 8446 for TLS 1.3.
	-- @function tls13_expand_label
	-- @within HKDFInstance
	-- @tparam string prk Pseudorandom Key (from the HKDF-Extract step or a previous Derive-Secret step).
	-- @tparam string label The label for the derived secret (e.g., "client_handshake_traffic_secret").
	-- @tparam string context A string containing the hash of the transcript of the handshake messages.
	-- @tparam number length The desired length in bytes for the derived secret.
	-- @treturn string The derived secret of the specified `length`.
	local function tls13_expand_label(prk, label, context, length)
		local hkdf_label_info = sp(">Hs1s1", length, "tls13 " .. label, context)
		return expand(prk, hkdf_label_info, length)
	end

	--- @type HKDFInstance
	local instance_methods = {
		hkdf = hkdf,
		extract = extract,
		expand = expand,
		tls13_expand_label = tls13_expand_label,
		close = function()
			--- Closes the HKDF instance and releases the underlying HMAC transform.
			-- This method is also called by the garbage collector.
			-- @function close
			if hmac_tfm and hmac_tfm.__close then
				hmac_tfm:__close()
				hmac_tfm = nil
			end
		end
	}
	return setmetatable(instance_methods, { __gc = instance_methods.close })
end
