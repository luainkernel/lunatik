--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- SKCIPHER (Synchronous Kernel Cipher) operations.
-- This module provides a Lua wrapper for SKCIPHER operations,
-- using the underlying 'crypto_skcipher' C module.
--
-- @module crypto.skcipher

local new = require("crypto_skcipher").new

--- SKCIPHER instance methods.
-- This table represents an SKCIPHER instance configured for a specific algorithm.
-- It is created by calling the main function of the `crypto.skcipher` module.
-- @type SkcipherCipherInstance
-- @field setkey Sets the encryption key.
-- @field ivsize Gets the required initialization vector (IV) size.
-- @field blocksize Gets the block size.
-- @field encrypt Encrypts plaintext.
-- @field decrypt Decrypts ciphertext.
-- @field close Release resources associated with this SKCIPHER instance.

--- Creates a new SKCIPHER cipher instance.
-- This function acts as the constructor for SKCIPHER instances.
-- @tparam string algname The algorithm name, e.g., "cbc(aes)", "ctr(aes)".
-- @treturn SkcipherCipherInstance An SKCIPHER instance table with methods for encryption and decryption.
-- @raise Error if `algname` is not a string or if C object creation fails.
-- @usage local aes_cbc = require("crypto.skcipher")("cbc(aes)")
return function (algname)
	if type(algname) ~= "string" then error("crypto.skcipher: constructor: algname must be a string", 2) end

	local tfm = new(algname) -- This is the C userdata object

	--- Sets the encryption key.
	-- @function setkey
	-- @within SkcipherCipherInstance
	-- @tparam string key The encryption key.
	-- @raise Error if key is not a string or if C operation fails.
	local function setkey(key)
		if type(key) ~= "string" then error("crypto.skcipher: setkey: key must be a string", 2) end
		return tfm:setkey(key) -- Call the C method on the tfm userdata
	end

	--- Gets the required initialization vector (IV) size.
	-- @function ivsize
	-- @within SkcipherCipherInstance
	-- @treturn number The required IV size in bytes.
	local function ivsize()
		return tfm:ivsize() -- Call the C method on the tfm userdata
	end

	--- Gets the block size of the SKCIPHER transform.
	-- Data processed by encrypt/decrypt should typically be a multiple of this size,
	-- depending on the cipher mode.
	-- @function blocksize
	-- @within SkcipherCipherInstance
	-- @treturn number The block size in bytes.
	local function blocksize()
		return tfm:blocksize()
	end

	--- Encrypts plaintext using the SKCIPHER transform.
	-- The IV (nonce) must be unique for each encryption operation with the same key for most modes.
	-- Plaintext length should be appropriate for the cipher mode (e.g., multiple of blocksize).
	-- @function encrypt
	-- @within SkcipherCipherInstance
	-- @tparam string iv The Initialization Vector. Its length must match `ivsize()`.
	-- @tparam string plaintext The data to encrypt.
	-- @treturn string The ciphertext.
	-- @raise Error on encryption failure, incorrect IV length, or allocation issues.
	local function encrypt(iv, plaintext) -- 'self' is implicitly the table, but not used here
		if type(iv) ~= "string" then error("crypto.skcipher: encrypt: iv must be a string", 2) end
		if type(plaintext) ~= "string" then error("crypto.skcipher: encrypt: plaintext must be a string", 2) end
		-- The C function tfm:encrypt takes iv and data separately
		return tfm:encrypt(iv, plaintext)
	end

	--- Decrypts ciphertext using the SKCIPHER transform.
	-- The IV must match the one used during encryption.
	-- Ciphertext length should be appropriate for the cipher mode.
	-- @function decrypt
	-- @within SkcipherCipherInstance
	-- @tparam string iv The Initialization Vector. Its length must match `ivsize()`.
	-- @tparam string ciphertext The data to decrypt.
	-- @treturn string The plaintext.
	-- @raise Error on decryption failure, incorrect IV length, or allocation issues.
	local function decrypt(iv, ciphertext) -- 'self' is implicitly the table, but not used here
		if type(iv) ~= "string" then error("crypto.skcipher: decrypt: iv must be a string", 2) end
		if type(ciphertext) ~= "string" then error("crypto.skcipher: decrypt: ciphertext must be a string", 2) end
		-- The C function tfm:decrypt takes iv and data separately
		return tfm:decrypt(iv, ciphertext)
	end

	--- Closes the cipher instance and releases underlying C resources.
	-- If not called explicitly, this will be called by the garbage collector.
	-- @function close
	-- @within SkcipherCipherInstance
	local function close()
		if tfm and tfm.__close then tfm:__close() end
		tfm = nil -- Allow C object to be garbage collected by Lunatik/kernel
	end

	--- @type SkcipherCipherInstance
	local skcipher = {
		setkey = setkey,
		ivsize = ivsize,
		blocksize = blocksize,
		encrypt = encrypt,
		decrypt = decrypt,
		close = close,
		__gc = close,
	}

	return setmetatable(skcipher, skcipher)
end