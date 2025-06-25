--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- SKCIPHER (Synchronous Kernel Cipher) operations.
-- This module provides a Lua wrapper for SKCIPHER operations,
-- using the underlying 'crypto_skcipher' C module.
-- As is, it’s very straight-forward, but could serve as a base
-- for higher-level api.
--
-- @classmod crypto.skcipher

local new = require("crypto_skcipher").new

--- SKCIPHER operations.
-- This table provides the `new` method to create SKCIPHER instances and also
-- serves as the prototype for these instances.
local SKCIPHER = {}

--- Creates a new SKCIPHER cipher instance.
-- @function SKCIPHER.new
-- @tparam string algname The algorithm name, e.g., "cbc(aes)", "ctr(aes)".
-- @treturn SKCIPHER An SKCIPHER instance table with methods for encryption and decryption.
-- @raise Error if `algname` is not a string or if C object creation fails.
-- @usage local aes_cbc = require("crypto.skcipher").new("cbc(aes)")
function SKCIPHER.new(algname)
	return setmetatable({c_tfm = new(algname)}, SKCIPHER)
end

--- Sets the encryption key.
-- @function SKCIPHER:setkey
-- @tparam string key The encryption key.
-- @raise Error if key is not a string or if C operation fails.
function SKCIPHER:setkey(key)
	return self.c_tfm:setkey(key)
end

--- Gets the required initialization vector (IV) size.
-- @function SKCIPHER:ivsize
-- @treturn number The required IV size in bytes.
function SKCIPHER:ivsize()
	return self.c_tfm:ivsize()
end

--- Gets the block size of the SKCIPHER transform.
-- @function SKCIPHER:blocksize
-- @treturn number The block size in bytes.
function SKCIPHER:blocksize()
	return self.c_tfm:blocksize()
end

--- Encrypts plaintext using the SKCIPHER transform.
-- @function SKCIPHER:encrypt
-- @tparam string iv The Initialization Vector. Its length must match `self:ivsize()`.
-- @tparam string plaintext The data to encrypt.
-- @treturn string The ciphertext.
-- @raise Error on encryption failure, incorrect IV length, or allocation issues.
function SKCIPHER:encrypt(iv, plaintext)
	return self.c_tfm:encrypt(iv, plaintext)
end

--- Decrypts ciphertext using the SKCIPHER transform.
-- @function SKCIPHER:decrypt
-- @tparam string iv The Initialization Vector. Its length must match `self:ivsize()`.
-- @tparam string ciphertext The data to decrypt.
-- @treturn string The plaintext.
-- @raise Error on decryption failure, incorrect IV length, or allocation issues.
function SKCIPHER:decrypt(iv, ciphertext)
	return self.c_tfm:decrypt(iv, ciphertext)
end

--- Closes the cipher instance and releases underlying C resources.
-- This method is also called by the garbage collector.
-- @function SKCIPHER:close
function SKCIPHER:close()
	if self.c_tfm and self.c_tfm.__close then
		self.c_tfm:__close()
		self.c_tfm = nil
	end
end

SKCIPHER.__gc = SKCIPHER.close
SKCIPHER.__index = SKCIPHER

return setmetatable(SKCIPHER, SKCIPHER)
