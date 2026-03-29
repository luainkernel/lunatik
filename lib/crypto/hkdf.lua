--- HMAC-based Extract-and-Expand KDF (RFC 5869).
-- @module crypto.hkdf

local shash = require("crypto").shash
local char, rep, sub = string.char, string.rep, string.sub

local HKDF = {}

--- Releases the HKDF instance.
-- @function HKDF:close
function HKDF:close()
	self.tfm:__close()
end

HKDF.__close = HKDF.close
HKDF.__index = HKDF

function HKDF.__len(self)
	return self.tfm:digestsize()
end

--- Creates a new HKDF instance.
-- @function HKDF.new
-- @tparam string alg Hash algorithm name (e.g., "sha256", "sha512").
-- @treturn HKDF HKDF instance.
-- @usage local hkdf = require("crypto.hkdf").new("sha256")
function HKDF.new(alg)
	local hmac = setmetatable({}, HKDF)
	hmac.tfm = shash("hmac(" .. alg .. ")")
	hmac.salt = rep("\0", #hmac)

	return hmac
end

--- Performs HMAC calculation.
-- @tparam string key HMAC key.
-- @tparam string data Data to hash.
-- @treturn string HMAC digest.
function HKDF:hmac(key, data)
	self.tfm:setkey(key)
	return self.tfm:digest(data)
end

--- Performs the HKDF Extract step.
-- @function HKDF:extract
-- @tparam[opt] string salt Salt value (defaults to hash_len zeros).
-- @tparam string ikm Input Keying Material.
-- @treturn string Pseudorandom Key (PRK).
function HKDF:extract(salt, ikm)
	return self:hmac((salt or self.salt), ikm)
end

--- Performs the HKDF Expand step.
-- @function HKDF:expand
-- @tparam string prk Pseudorandom Key.
-- @tparam[opt] string info Context or application-specific information.
-- @tparam number length Desired Output Keying Material (OKM) length in bytes.
-- @treturn string Output Keying Material.
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

--- Performs the full HKDF (Extract + Expand) operation.
-- @function HKDF:hkdf
-- @tparam[opt] string salt Salt value.
-- @tparam string ikm Input Keying Material.
-- @tparam[opt] string info Context or application-specific information.
-- @tparam number length Desired Output Keying Material length.
-- @treturn string Output Keying Material.
function HKDF:hkdf(salt, ikm, info, length)
	return self:expand(self:extract(salt, ikm), info, length)
end

return HKDF

