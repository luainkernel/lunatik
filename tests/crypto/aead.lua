--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
local aead = require"crypto.aead"
local util = require("util")
local test = util.test
local hex2bin = util.hex2bin
local bin2hex = util.bin2hex

test("AEAD AES-128-GCM encrypt", function()
	local c = aead.new"gcm(aes)"
	c:setkey"0123456789abcdef"
	c:setauthsize(16)

	local expected = hex2bin"95be1ddc3dd13cdd2d8ffcc391561ade661d5b696ede5a918e"
	-- The encrypt method returns ciphertext_with_tag, tag_length. We only need the first one for this assertion.
	local result = c:encrypt("abcdefghijkl", "plaintext", "0123456789abcdef")
	assert(result == expected, "Expected: " .. bin2hex(expected) .. ", got: " .. bin2hex(result))
end)

test("AEAD AES-128-GCM decrypt", function()
	local c = aead.new"gcm(aes)"
	c:setkey"0123456789abcdef"
	c:setauthsize(16)

	local ciphertext = hex2bin"95be1ddc3dd13cdd2d8ffcc391561ade661d5b696ede5a918e"
	local expected = "plaintext"
	local result = c:decrypt("abcdefghijkl", ciphertext, "0123456789abcdef")
	-- We use bin2hex for the error message, as the result is a binary string which may not be printable.
	assert(result == expected, "Expected: " .. bin2hex(expected) .. ", got: " .. bin2hex(result))
end)

test("AEAD AES-128-GCM ivsize and authsize", function()
	local c = aead.new"gcm(aes)"
	assert(c:ivsize() == 12, "IV size for AES-128-GCM should be 12 bytes")
	c:setauthsize(16)
	assert(c:authsize() == 16, "Auth size for AES-128-GCM should be 16 bytes")
end)

test("AEAD AES-128-GCM setkey with invalid key length", function()
	local c = aead.new"gcm(aes)"
	local status, err = pcall(c.setkey, c, "0123456789abcde") -- 15 bytes, invalid for AES-128
	assert(not status, "setkey with invalid key length should fail")
	assert(err == "EINVAL", "Error code should be 'EINVAL', got: " .. err)
end)

test("AEAD AES-128-GCM setauthsize with invalid tag length", function()
	local c = aead.new"gcm(aes)"
	local status, err = pcall(c.setauthsize, c, 11) -- 11 bytes, invalid for GCM (must be 4, 8, 12, 13, 14, 15, 16)
	assert(not status, "setauthsize with invalid tag length should fail")
	assert(err == "EINVAL", "Error code should be 'EINVAL', got: " .. err)
end)

test("AEAD AES-128-GCM encrypt with incorrect IV length", function()
	local c = aead.new"gcm(aes)"
	c:setkey"0123456789abcdef"
	c:setauthsize(16)
	local err_msg = "incorrect IV length"
	local status, err = pcall(c.encrypt, c, "abcdefghijk", "plaintext") -- 11 bytes, incorrect IV length
	assert(not status, "encrypt with incorrect IV length should fail")
	assert(err:find(err_msg), "Error message should contain '" .. err_msg .. "', got: " .. err)
end)

test("AEAD AES-128-GCM decrypt with incorrect IV length", function()
	local c = aead.new"gcm(aes)"
	c:setkey"0123456789abcdef"
	c:setauthsize(16)
	local ciphertext = hex2bin"95be1ddc3dd13cdd2d8ffcc391561ade661d5b696ede5a918e"
	local err_msg = "incorrect IV length"
	local status, err = pcall(c.decrypt, c, "abcdefghijk", ciphertext) -- 11 bytes, incorrect IV length
	assert(not status, "decrypt with incorrect IV length should fail")
	assert(err:find(err_msg), "Error message should contain '" .. err_msg .. "', got: " .. err)
end)

test("AEAD AES-128-GCM decrypt with input data too short for tag", function()
	local c = aead.new"gcm(aes)"
	c:setkey"0123456789abcdef"
	c:setauthsize(16)
	local short_ciphertext = hex2bin"95be1ddc3dd13cdd2d8ffcc391561ade661d5b696ede5a918" -- Missing last byte of tag
	local status, err = pcall(c.decrypt, c, "abcdefghijkl", short_ciphertext, "0123456789abcdef")
	assert(not status, "decrypt with input data too short for tag should fail")
	assert(err == "EBADMSG", "Error code should be 'EBADMSG', got: " .. err)
end)

test("AEAD AES-128-GCM decrypt with authentication failure", function()
	local c = aead.new"gcm(aes)"
	c:setkey"0123456789abcdef"
	c:setauthsize(16)
	local tampered_ciphertext = hex2bin"95be1ddc3dd13cdd2d8ffcc391561ade661d5b696ede5a918f" -- Last byte of tag tampered
	local status, err = pcall(c.decrypt, c, "abcdefghijkl", tampered_ciphertext)
	assert(not status, "decrypt with tampered data should fail")
	assert(err == "EBADMSG", "Error code should be 'EBADMSG', got: " .. err)
end)

