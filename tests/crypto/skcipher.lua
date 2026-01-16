--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local skcipher = require("crypto.skcipher")
local util = require("util")
local test = util.test
local hex2bin = util.hex2bin

test("SKCIPHER AES-128-CBC encrypt", function()
	local c = skcipher.new"cbc(aes)"
	-- The plaintext must be a multiple of the block size (16 bytes for AES-128)
	-- If the plaintext is not a multiple of the block size, it should be padded.
	local plaintext = "This is a test!!"
	local ciphertext = hex2bin"d05e07d91a4b4cd10951f8cf195f27b5"
	c:setkey"0123456789abcdef"

	local result = c:encrypt("fedcba9876543210", plaintext)
	assert(result == ciphertext, "Cipher text mismatch")
end)

test("SKCIPHER AES-128-CBC decrypt", function()
	local c = skcipher.new"cbc(aes)"
	local plaintext = "This is a test!!"
	local ciphertext = hex2bin"d05e07d91a4b4cd10951f8cf195f27b5"
	c:setkey"0123456789abcdef"

	local result = c:decrypt("fedcba9876543210", ciphertext)
	assert(result == plaintext, "Plain text mismatch")
end)

test("SKCIPHER AES-128-CBC ivsize and blocksize", function()
	local c = skcipher.new"cbc(aes)"
	assert(c:ivsize() == 16, "IV size for AES-128-CBC should be 16 bytes")
	assert(c:blocksize() == 16, "Block size for AES-128-CBC should be 16 bytes")
end)

test("SKCIPHER AES-128-CBC setkey with invalid key length", function()
	local c = skcipher.new"cbc(aes)"
	local status, err = pcall(c.setkey, c, "0123456789abcde") -- 15 bytes, invalid for AES-128
	assert(not status, "setkey with invalid key length should fail")
	assert(err == "EINVAL", "Error code should be 'EINVAL', got: " .. err)
end)

test("SKCIPHER AES-128-CBC encrypt with incorrect IV length", function()
	local c = skcipher.new"cbc(aes)"
	local plaintext = "This is a test!!"
	c:setkey"0123456789abcdef"
	local status, err = pcall(c.encrypt, c, "fedcba987654321", plaintext) -- 15 bytes, incorrect IV length
	assert(not status, "encrypt with incorrect IV length should fail")
	assert(string.find(err, "incorrect IV length"), "Error message should indicate incorrect IV length: " .. err)
end)

test("SKCIPHER AES-128-CBC decrypt with incorrect IV length", function()
	local c = skcipher.new"cbc(aes)"
	local ciphertext = hex2bin"d05e07d91a4b4cd10951f8cf195f27b5"
	c:setkey"0123456789abcdef"
	local status, err = pcall(c.decrypt, c, "fedcba987654321", ciphertext) -- 15 bytes, incorrect IV length
	assert(not status, "decrypt with incorrect IV length should fail")
	assert(string.find(err, "incorrect IV length"), "Error message should indicate incorrect IV length " .. err)
end)

test("SKCIPHER AES-128-CBC encrypt with data not multiple of blocksize", function()
	local c = skcipher.new"cbc(aes)"
	local plaintext = "This is a test!!!" -- 17 bytes, not multiple of 16
	c:setkey"0123456789abcdef"
	local status, err = pcall(c.encrypt, c, "fedcba9876543210", plaintext)
	assert(not status, "encrypt with data not multiple of blocksize should fail")
	assert(err == "EINVAL", "Error code should be 'EINVAL', got: " .. err)
end)

test("SKCIPHER AES-128-CBC decrypt with data not multiple of blocksize", function()
	local c = skcipher.new"cbc(aes)"
	local ciphertext = hex2bin"d05e07d91a4b4cd10951f8cf195f27b5" .. "00" -- 17 bytes, not multiple of 16
	c:setkey"0123456789abcdef"
	local status, err = pcall(c.decrypt, c, "fedcba9876543210", ciphertext)
	assert(not status, "decrypt with data not multiple of blocksize should fail")
	assert(err == "EINVAL", "Error code should be 'EINVAL', got: " .. err)
end)

