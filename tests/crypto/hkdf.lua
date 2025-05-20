--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
local new = require("crypto.hkdf").new
local util = require("util")
local bin2hex, hex2bin = util.bin2hex, util.hex2bin

local test, expected, result

xpcall(
  function ()
		local h = new"sha256"
		print"HKDF test vectors from RFC 5869, Appendix A"

		test = "RFC5869 1"
		expected = hex2bin"3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
		result = h:hkdf(
			hex2bin"000102030405060708090a0b0c",
			hex2bin"0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b",
			hex2bin"f0f1f2f3f4f5f6f7f8f9",
			42
		)
		assert(result == expected)

		test = "RFC5869 2"
		expected = hex2bin"b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71cc30c58179ec3e87c14c01d5c1f3434f1d87"
		result = h:hkdf(
			hex2bin"606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeaf",
			hex2bin"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f",
			hex2bin"b0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff",
			82
		)
		assert(result == expected)

		test = "RFC5869 3"
		expected = hex2bin"8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"
		result = h:hkdf(
			"",
			hex2bin"0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b",
			"",
			42
		)
		assert(result == expected)


		print"HKDF-Expand-Label examples from https://quic.xargs.org/#client-initial-keys-calc"

		test = "HKDF-Expand-Label init_secret"
		expected = hex2bin"f016bb2dc9976dea2726c4e61e738a1e3680a2487591dc76b2aee2ed759822f6"
		result = h:extract(
			hex2bin"38762cf7f55934b34d179ae6a4c80cadccbb7f0a",
			hex2bin"0001020304050607"
		)
		assert(result == expected)

		test = "HKDF-Expand-Label csecret"
		expected = hex2bin"47c6a638d4968595cc20b7c8bc5fbfbfd02d7c17cc67fa548c043ecb547b0eaa" -- This is the PRK from the previous step
		result = h:tls13_expand_label(result, "client in", "", 32)
		assert(result == expected)
		local csecret = result

		test = "HKDF-Expand-Label client_init_key"
		expected = hex2bin"b14b918124fda5c8d79847602fa3520b"
		result = h:tls13_expand_label(csecret, "quic key", "", 16)
		assert(result == expected)

		test = "HKDF-Expand-Label client_init_iv"
		expected = hex2bin"ddbc15dea80925a55686a7df"
		result = h:tls13_expand_label(csecret, "quic iv", "", 12)
		assert(result == expected)

		print"All HKDF tests passed"
	end,

	function(msg)
		print("Test " .. test .. " FAILED")
		print("Result: " .. bin2hex(result))
		print("Expected: " .. bin2hex(expected))
		print(msg)
		print(debug.traceback())
	end
)

