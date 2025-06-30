--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local shash = require("crypto_shash")
local util = require("util")
local test = util.test
local hex2bin = util.hex2bin

test("crypto_shash.new and digestsize", function()
	local hasher = shash.new("sha256")
	assert(hasher, "Failed to create sha256 hasher")
	assert(hasher:digestsize() == 32, "SHA256 digest size should be 32 bytes")

	local hmac_hasher = shash.new("hmac(sha256)")
	assert(hmac_hasher, "Failed to create hmac(sha256) hasher")
	assert(hmac_hasher:digestsize() == 32, "HMAC(SHA256) digest size should be 32 bytes")
end)

test("crypto_shash:digest (single-shot)", function()
	local hasher = shash.new("sha256")
	local data = "The quick brown fox jumps over the lazy dog"
	local expected_digest = hex2bin("d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")
	local digest = hasher:digest(data)
	assert(digest == expected_digest, "SHA256 digest mismatch")

	local hmac_hasher = shash.new("hmac(sha256)")
	local key = "key"
	local hmac_data = "The quick brown fox jumps over the lazy dog"
	local expected_hmac_digest = hex2bin("f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
	hmac_hasher:setkey(key)
	local hmac_digest = hmac_hasher:digest(hmac_data)
	assert(hmac_digest == expected_hmac_digest, "HMAC(SHA256) digest mismatch")
end)

test("crypto_shash:init, update, final (multi-part)", function()
	local hasher = shash.new("sha256")
	local data1 = "The quick brown "
	local data2 = "fox jumps over "
	local data3 = "the lazy dog"
	local expected_digest = hex2bin("d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")

	hasher:init()
	hasher:update(data1)
	hasher:update(data2)
	hasher:update(data3)
	local digest = hasher:final()
	assert(digest == expected_digest, "Multi-part SHA256 digest mismatch")
end)

test("crypto_shash:finup", function()
	local hasher = shash.new("sha256")
	local data1 = "The quick brown "
	local data2 = "fox jumps over the lazy dog"
	local expected_digest = hex2bin("d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")

	hasher:init()
	hasher:update(data1)
	local digest = hasher:finup(data2)
	assert(digest == expected_digest, "Finup SHA256 digest mismatch")
end)

test("crypto_shash:export and import functionality", function()
	local hasher1 = shash.new("sha256")
	local hasher2 = shash.new("sha256")

	local data1 = "Hello, "
	local data2 = "world!"
	local full_data = data1 .. data2

	-- Test with hasher1: init, update, export
	hasher1:init()
	hasher1:update(data1)
	local exported_state = hasher1:export()

	-- Test with hasher2: init, import, update, final
	hasher2:init()
	hasher2:import(exported_state)
	hasher2:update(data2)
	local digest2 = hasher2:final()

	-- Compute full digest with a third hasher for comparison
	local hasher_full = shash.new("sha256")
	local digest_full = hasher_full:digest(full_data)

	assert(digest2 == digest_full, "Digests do not match after export/import")

	-- Test with hasher1: finup (after export)
	local digest1_finup = hasher1:finup(data2)
	assert(digest1_finup == digest_full, "Finup digest after export does not match full digest")

	-- Test with hasher1: final (after export)
	local hasher3 = shash.new("sha256")
	hasher3:init()
	hasher3:update(data1)
	local exported_state_2 = hasher3:export()
	local digest3 = hasher3:final() -- Finalize after export, should be digest of data1
	local hasher_data1 = shash.new("sha256")
	local digest_data1 = hasher_data1:digest(data1)
	assert(digest3 == digest_data1, "Final digest after export does not match digest of data1")

	-- Test with hasher2: import again and finalize
	local hasher4 = shash.new("sha256")
	hasher4:init()
	hasher4:import(exported_state_2)
	local digest4 = hasher4:final()
	assert(digest4 == digest_data1, "Imported state final digest does not match digest of data1")
end)

