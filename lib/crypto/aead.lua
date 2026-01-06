--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- AEAD (Authenticated Encryption with Associated Data) operations.
-- This module provides a Lua wrapper for AEAD operations,
-- using the underlying 'crypto_aead' C module.
--
-- @module crypto.aead

local new = require("crypto_aead").new
local sub = string.sub

--- Prototype for AEAD instances.
-- Objects of this type are created by `AeadModule.new()`.
-- @type AEAD
local AEAD = {}

--- Closes the cipher instance and releases underlying C resources.
-- If not called explicitly, this will be called by the garbage collector.
function AEAD:close()
	if self.tfm then self.tfm:__close() end
	self.tfm = nil -- Allow the C object to be garbage collected by Lua
end

AEAD.__close = AEAD.close
AEAD.__index = AEAD

--- Creates a new AEAD cipher instance.
-- @function new
-- @tparam string algname The algorithm name, e.g., "gcm(aes)".
-- @treturn Aead An AEAD instance.
-- @raise Error if C object creation fails.
-- @usage
--  local aead = require("crypto.aead")
--  local gcm_aes = aead.new("gcm(aes)")
-- @within aead
function AEAD.new(algname)
	return setmetatable({tfm = new(algname)}, AEAD)
end

--- Sets the encryption key.
-- @tparam string key The encryption key.
-- @raise Error if setting the key fails (e.g., invalid key length for the algorithm).
function AEAD:setkey(key)
	return self.tfm:setkey(key)
end

--- Sets the authentication tag size.
-- @tparam number size The desired tag size in bytes.
-- @raise Error if C operation fails.
function AEAD:setauthsize(size)
	return self.tfm:setauthsize(size)
end

--- Gets the required nonce/IV size.
-- @treturn number The required IV size in bytes.
function AEAD:ivsize()
	return self.tfm:ivsize()
end

--- Gets the authentication tag size.
-- @treturn number The current tag size in bytes.
function AEAD:authsize()
	return self.tfm:authsize()
end

--- Encrypts plaintext.
-- @tparam string nonce The unique nonce. Its length should match `self:ivsize()`.
-- @tparam string plaintext The plaintext to encrypt.
-- @tparam[opt] string aad Additional Authenticated Data. Defaults to an empty string if nil.
-- @treturn string ciphertext_with_tag The encrypted data including the authentication tag.
-- @treturn number tag_length The length of the authentication tag in bytes (equal to `self:authsize()`).
-- @raise Error if encryption fails in C.
function AEAD:encrypt(nonce, plaintext, aad)
	aad = aad or ""
	-- The C function c_tfm:encrypt returns (aad || ciphertext || tag).
	return sub(self.tfm:encrypt(nonce, aad .. plaintext, #aad), #aad + 1), self.tfm:authsize()
end

--- Decrypts ciphertext.
-- @tparam string nonce The unique nonce (must match encryption). Its length should match `self:ivsize()`.
-- @tparam string ciphertext_with_tag The ciphertext including the tag.
-- @tparam[opt] string aad Additional Authenticated Data (must match encryption). Defaults to an empty string if nil.
-- @treturn string plaintext The decrypted data on success.
-- @raise Error if decryption fails in C (e.g., tag mismatch).
function AEAD:decrypt(nonce, ciphertext_with_tag, aad)
	aad = aad or ""
	-- The C function c_tfm:decrypt returns (aad || plaintext)
	return sub(self.tfm:decrypt(nonce, aad .. ciphertext_with_tag, #aad), #aad + 1)
end

return AEAD

