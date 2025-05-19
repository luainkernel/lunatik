--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- AEAD (Authenticated Encryption with Associated Data) operations.
-- This module provides a Lua wrapper for AEAD operations,
-- using the underlying 'crypto_aead' C module.
--
-- @module crypto.aead

local new = require("crypto_aead").new
local sub = string.sub

--- AEAD instance methods.
-- This table represents an AEAD instance configured for a specific algorithm.
-- It is created by calling the main function of the `crypto.aead` module.
-- @type AeadCipherInstance
-- @field setkey Sets the encryption key.
-- @field setauthsize Sets the authentication tag size.
-- @field ivsize Gets the required nonce/IV size.
-- @field authsize Gets the authentication tag size.
-- @field encrypt Encrypts plaintext.
-- @field decrypt Decrypts ciphertext.
-- @field close Release resources associated with this AEAD instance.

--- Creates a new AEAD cipher instance.
-- This function acts as the constructor for AEAD instances.
-- @tparam string algname The algorithm name, e.g., "gcm(aes)".
-- @treturn AeadCipherInstance An AEAD instance table with methods for encryption and decryption.
-- @raise Error if `algname` is not a string or if C object creation fails.
-- @usage local gcm_aes = require("crypto.aead")("gcm(aes)")
return function (algname)
	if type(algname) ~= "string" then error("crypto.aead: constructor: algname must be a string", 2) end

	local tfm = new(algname) -- This is the C userdata object

	--- Sets the encryption key.
	-- @function setkey
	-- @within AeadCipherInstance
	-- @tparam string key The encryption key.
	-- @raise Error if key is not a string or if C operation fails.
	local function setkey(key)
		if type(key) ~= "string" then error("crypto.aead: setkey: key must be a string", 2) end
		return tfm:setkey(key) -- Call the C method on the tfm userdata
	end

	--- Sets the authentication tag size.
	-- @function setauthsize
	-- @within AeadCipherInstance
	-- @tparam number size The desired tag size in bytes.
	-- @raise Error if size is not a number or if C operation fails.
	local function setauthsize(size)
		if type(size) ~= "number" then error("crypto.aead: setauthsize: size must be a number", 2) end
		return tfm:setauthsize(size) -- Call the C method on the tfm userdata
	end

	--- Gets the required nonce/IV size.
	-- @function ivsize
	-- @within AeadCipherInstance
	-- @treturn number The required IV size in bytes.
	local function ivsize()
		return tfm:ivsize() -- Call the C method on the tfm userdata
	end

	--- Gets the authentication tag size.
	-- @function authsize
	-- @within AeadCipherInstance
	-- @treturn number The current tag size in bytes.
	local function authsize()
		return tfm:authsize() -- Call the C method on the tfm userdata
	end

	--- Encrypts plaintext.
	-- @function encrypt
	-- @within AeadCipherInstance
	-- @tparam string nonce The unique nonce (Number used once). Its length should match `ivsize()`.
	-- @tparam string plaintext The plaintext to encrypt.
	-- @tparam[opt] string aad Additional Authenticated Data. Defaults to an empty string if nil.
	-- @treturn string ciphertext_with_tag The encrypted data including the authentication tag.
	-- @treturn number tag_length The length of the authentication tag in bytes (equal to `authsize()`).
	-- @raise Error on type mismatch or if encryption fails in C.
	local function encrypt(nonce, plaintext, aad) -- 'self' is implicitly the table, but not used here
		if type(nonce) ~= "string" then error("crypto.aead: encrypt: nonce must be a string", 2) end
		if type(plaintext) ~= "string" then error("crypto.aead: encrypt: plaintext must be a string", 2) end
		if aad ~= nil and type(aad) ~= "string" then error("encrypt: AAD must be a string or nil", 2) end
		aad = aad or ""
		-- The C function tfm:encrypt returns (aad || ciphertext || tag).
		-- Extract (ciphertext || tag) from (aad || ciphertext || tag).
		return sub(tfm:encrypt(nonce, aad .. plaintext, #aad), #aad + 1), tfm:authsize()
	end

	--- Decrypts ciphertext.
	-- @function decrypt
	-- @within AeadCipherInstance
	-- @tparam string nonce The unique nonce (must match encryption). Its length should match `ivsize()`.
	-- @tparam string ciphertext_with_tag The ciphertext including the tag.
	-- @tparam[opt] string aad Additional Authenticated Data (must match encryption). Defaults to an empty string if nil.
	-- @treturn string plaintext The decrypted data on success.
	-- @raise Error on type mismatch or if decryption fails in C (e.g., tag mismatch).
	local function decrypt(nonce, ciphertext_with_tag, aad) -- 'self' is implicitly the table, but not used here
		if type(nonce) ~= "string" then error("crypto.aead: decrypt: nonce must be a string", 2) end
		if type(ciphertext_with_tag) ~= "string" then error("crypto.aead: decrypt: ciphertext_with_tag must be a string", 2) end
		if aad ~= nil and type(aad) ~= "string" then error("decrypt: AAD must be a string or nil", 2) end
		aad = aad or ""
		-- The C function tfm:decrypt returns (aad || plaintext)
		return sub(tfm:decrypt(nonce, aad .. ciphertext_with_tag, #aad), #aad + 1)
	end

	--- Closes the cipher instance and releases underlying C resources.
	-- If not called explicitly, this will be called by the garbage collector.
	-- @function close
	-- @within AeadCipherInstance
	local function close()
		if tfm and tfm.__close then tfm:__close() end
		tfm = nil
	end

	--- @type AeadCipherInstance
	local aead = {
		setkey = setkey,
		setauthsize = setauthsize,
		ivsize = ivsize,
		authsize = authsize,
		encrypt = encrypt,
		decrypt = decrypt,
		close = close,
		__gc = close,
	}

	return setmetatable(aead, aead)
end