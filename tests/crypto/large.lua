--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto large test (see large.sh).

local crypto = require("crypto")
local test = require("tests.lib").test
local sizes = require("tests.crypto.large_sizes")

local concat, insert = table.concat, table.insert
local char, rep, sub = string.char, string.rep, string.sub

local KEY <const> = "0123456789abcdef"
local IV <const> = "fedcba9876543210"
local NONCE <const> = "abcdefghijkl"
local GCM_COUNTER <const> = NONCE .. "\0\0\0\2" -- gcm(aes) ciphers with ctr(aes) from the second counter
local BLOCK <const> = 16
local ENOMEM <const> = "not enough memory"
local EBADMSG <const> = "EBADMSG"

local page = sizes.page
local spanning = rep("a", page) .. rep("b", page) .. rep("c", BLOCK)
local associated = rep("d", page) .. rep("e", page + 1)
local oversized = rep("x", sizes.kmalloc + page)

local function keyed(new, algorithm)
	local c = new(algorithm)
	c:setkey(KEY)
	return c
end

local function cbc()
	return keyed(crypto.skcipher, "cbc(aes)")
end

local function gcm()
	return keyed(crypto.aead, "gcm(aes)")
end

local function chained(c, data)
	local iv, parts = IV, {}
	for i = 1, #data, page do
		local part = c:encrypt(iv, sub(data, i, i + page - 1))
		insert(parts, part)
		iv = sub(part, -BLOCK)
	end
	return concat(parts)
end

local function flipped(data, at)
	return sub(data, 1, at - 1) .. char(data:byte(at) ~ 1) .. sub(data, at + 1)
end

local function refused(expected, name, method, c, ...)
	local ok, err = pcall(method, c, ...)
	assert(not ok, name .. " should be refused")
	assert(err == expected, name .. ": expected '" .. expected .. "', got: " .. tostring(err))
end

test("SKCIPHER AES-128-CBC data spanning pages matches its pages chained", function()
	local c = cbc()
	local ciphertext = c:encrypt(IV, spanning)
	assert(ciphertext == chained(c, spanning), "ciphertext differs from the chained pages")
	assert(c:decrypt(IV, ciphertext) == spanning, "round-trip mismatch")
end)

test("AEAD AES-128-GCM data and associated data spanning pages", function()
	local c = gcm()
	local sealed = c:encrypt(NONCE, spanning, associated)
	assert(#sealed == #spanning + c:authsize(), "sealed length mismatch")

	local ctr = keyed(crypto.skcipher, "ctr(aes)")
	assert(sub(sealed, 1, #spanning) == ctr:encrypt(GCM_COUNTER, spanning), "ciphertext differs from ctr(aes)")
	assert(c:decrypt(NONCE, sealed, associated) == spanning, "round-trip mismatch")

	refused(EBADMSG, "a flip in the data's last page", c.decrypt, c, NONCE, flipped(sealed, 2 * page + 1), associated)
	refused(EBADMSG, "a flip in the associated data's last page", c.decrypt, c, NONCE, sealed,
		flipped(associated, #associated))
end)

test("SKCIPHER AES-128-CBC data past KMALLOC_MAX_SIZE", function()
	local c = cbc()
	refused(ENOMEM, "encrypt", c.encrypt, c, IV, oversized)
	refused(ENOMEM, "decrypt", c.decrypt, c, IV, oversized)
end)

test("AEAD AES-128-GCM data or associated data past KMALLOC_MAX_SIZE", function()
	local c = gcm()
	refused(ENOMEM, "encrypt", c.encrypt, c, NONCE, oversized)
	refused(ENOMEM, "encrypt with associated data", c.encrypt, c, NONCE, "", oversized)
	refused(ENOMEM, "decrypt", c.decrypt, c, NONCE, oversized)
	refused(ENOMEM, "decrypt with associated data", c.decrypt, c, NONCE, rep("y", c:authsize()), oversized)
end)

