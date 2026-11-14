--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto large test (see large.sh).

local crypto = require("crypto")
local lib = require("tests.lib")
local test = lib.test
local sizes = require("tests.crypto.large_sizes")

local concat, insert = table.concat, table.insert
local char, rep, sub = string.char, string.rep, string.sub

local CBC <const> = "cbc(aes)"
local GCM <const> = "gcm(aes)"
local CTR <const> = "ctr(aes)"
local LZ4 <const> = "lz4"
local KEY <const> = "0123456789abcdef"
local IV <const> = "fedcba9876543210"
local NONCE <const> = "abcdefghijkl"
local GCM_COUNTER <const> = NONCE .. "\0\0\0\2" -- gcm(aes) ciphers with ctr(aes) from the second counter
local BLOCK <const> = 16
local ENOMEM <const> = "not enough memory"
local EBADMSG <const> = "EBADMSG"
local EINVAL <const> = "EINVAL"
local SCRATCH <const> = 128 * 1024 -- what scomp bounds the input and the output by on 6.14 and earlier
local LZ4_BOUND <const> = SCRATCH + SCRATCH // 255 + 16 -- LZ4_COMPRESSBOUND(SCRATCH), lz4's worst output

local page = sizes.page
local spanning = rep("a", page) .. rep("b", page) .. rep("c", BLOCK)
local associated = rep("d", page) .. rep("e", page + 1)
local oversized = rep("x", sizes.kmalloc + page)
local paged = sub(spanning, 1, page + BLOCK) -- within the 128 KiB 6.14 and earlier compress in software
local bounded = sizes.bounded
local past = bounded and "raises " .. EINVAL or "round-trips"

-- the algorithms the cases allocate, before they run, so large.sh skips the test where the kernel lacks one
lib.alloc(crypto.skcipher, CBC)
lib.alloc(crypto.aead, GCM)
lib.alloc(crypto.skcipher, CTR)
lib.alloc(crypto.comp, LZ4)

local function keyed(new, algorithm)
	local c = new(algorithm)
	c:setkey(KEY)
	return c
end

local function cbc()
	return keyed(crypto.skcipher, CBC)
end

local function gcm()
	return keyed(crypto.aead, GCM)
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

local function unauthentic(name, plain, err)
	assert(plain == nil and err == EBADMSG, name .. ": expected nil and '" .. EBADMSG .. "', got: " ..
		tostring(plain) .. ", " .. tostring(err))
end

local function refused(expected, name, method, c, ...)
	local ok, err = pcall(method, c, ...)
	assert(not ok, name .. " should be refused")
	assert(err == expected, name .. ": expected '" .. expected .. "', got: " .. tostring(err))
end

local function roundtrip(c, data, max_len)
	local packed = c:compress(data, max_len)
	assert(c:decompress(packed, #data) == data, "round-trip mismatch")
	return #packed
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

	local ctr = keyed(crypto.skcipher, CTR)
	assert(sub(sealed, 1, #spanning) == ctr:encrypt(GCM_COUNTER, spanning), "ciphertext differs from ctr(aes)")
	assert(c:decrypt(NONCE, sealed, associated) == spanning, "round-trip mismatch")

	unauthentic("a flip in the data's last page", c:decrypt(NONCE, flipped(sealed, 2 * page + 1), associated))
	unauthentic("a flip in the associated data's last page", c:decrypt(NONCE, sealed, flipped(associated, #associated)))
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

test("COMP lz4 data past a page round-trips", function()
	local c = crypto.comp(LZ4)
	assert(roundtrip(c, paged, 2 * #paged) < #paged, "compressed data is not shorter than the original")
end)

test("COMP lz4 data of 128 KiB round-trips", function()
	local c = crypto.comp(LZ4)
	roundtrip(c, rep("z", SCRATCH), page)
end)

test("COMP lz4 data past 128 KiB " .. past, function()
	local c = crypto.comp(LZ4)
	local data = rep("z", SCRATCH + 1)
	if bounded then
		refused(EINVAL, "compress", c.compress, c, data, page)
	else
		roundtrip(c, data, page)
	end
end)

test("COMP lz4 output past 128 KiB " .. past, function()
	local c = crypto.comp(LZ4)
	local data = cbc():encrypt(IV, rep("z", SCRATCH)) -- what lz4 cannot shrink
	if bounded then
		refused(EINVAL, "compress", c.compress, c, data, LZ4_BOUND)
	else
		assert(roundtrip(c, data, LZ4_BOUND) > SCRATCH, "compressed data is not past 128 KiB")
	end
end)

test("COMP lz4 data or output past KMALLOC_MAX_SIZE", function()
	local c = crypto.comp(LZ4)
	refused(ENOMEM, "compress", c.compress, c, oversized, page)
	refused(ENOMEM, "decompress", c.decompress, c, oversized, page)
	refused(ENOMEM, "compress output", c.compress, c, "x", #oversized)
	refused(ENOMEM, "decompress output", c.decompress, c, "x", #oversized)
end)

