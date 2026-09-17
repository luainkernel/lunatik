--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.tls test (see run.sh).
--

local ltls = require("linux.tls")
local test = require("util").test

-- the SOL_TLS option names, at the values uapi/linux/tls.h gives them
local options = { TX = 1, RX = 2, TX_ZEROCOPY_RO = 3, RX_EXPECT_NO_PAD = 4 }

-- the halves TLS_VERSION_NUMBER composes 0x0303 and 0x0304 from; autogen cannot
-- emit the composed numbers, so the `tls` module builds them from these
local halves = {
	["1_2_VERSION_MAJOR"] = 3, ["1_2_VERSION_MINOR"] = 3,
	["1_3_VERSION_MAJOR"] = 3, ["1_3_VERSION_MINOR"] = 4,
}

local ciphers = {
	AES_GCM_128 = 51, AES_GCM_256 = 52, AES_CCM_128 = 53,
	CHACHA20_POLY1305 = 54, SM4_GCM = 55, SM4_CCM = 56,
}

-- absent from the header before 6.1
local recent = { ARIA_GCM_128 = 57, ARIA_GCM_256 = 58 }

-- TLS_CIPHER_MIN..TLS_CIPHER_MAX, the range get_cipher_desc resolves (net/tls/tls.h)
local MIN <const> = 51
local MAX <const> = 58

-- the four key material fields a tls12_crypto_info_* carries after the header
local fields = { "IV", "KEY", "SALT", "REC_SEQ" }

-- the one cipher whose nonce needs no salt
local NOSALT <const> = "CHACHA20_POLY1305_SALT_SIZE"

local header = { version = { offset = 0, size = 2 }, cipher_type = { offset = 2, size = 2 } }

test("linux.tls carries the SOL_TLS option names at their uapi values", function()
	for name, value in pairs(options) do
		assert(ltls[name] == value, name .. ": " .. tostring(ltls[name]))
	end
end)

test("linux.tls carries the halves the TLS version numbers are built from", function()
	for name, value in pairs(halves) do
		assert(ltls[name] == value, name .. ": " .. tostring(ltls[name]))
	end
end)

test("linux.tls.cipher carries every cipher id at its uapi value", function()
	for name, value in pairs(ciphers) do
		assert(ltls.cipher[name] == value, name .. ": " .. tostring(ltls.cipher[name]))
	end
	for name, value in pairs(recent) do
		assert(ltls.cipher[name] == nil or ltls.cipher[name] == value,
			name .. ": " .. tostring(ltls.cipher[name]))
	end
end)

test("every linux.tls.cipher entry is a distinct id inside the range the kernel resolves", function()
	local named = {}
	for name, value in pairs(ltls.cipher) do
		assert(value >= MIN and value <= MAX, name .. " is outside TLS_CIPHER_MIN..MAX: " .. value)
		assert(named[value] == nil, name .. " repeats the value of " .. tostring(named[value]))
		named[value] = name
	end
end)

test("linux.tls.size gives the four key material sizes of every cipher", function()
	for name in pairs(ltls.cipher) do
		for _, field in ipairs(fields) do
			local key = name .. "_" .. field .. "_SIZE"
			local size = ltls.size[key]
			assert(size ~= nil, key .. " is missing")
			assert(size > 0 or key == NOSALT, key .. " is not a positive size: " .. size)
		end
	end
	assert(ltls.size[NOSALT] == 0, NOSALT .. ": " .. tostring(ltls.size[NOSALT]))
end)

test("linux.tls.layout.crypto_info is the header a keying setsockopt reads first", function()
	local info = ltls.layout.crypto_info
	assert(info.size == 4, "size: " .. tostring(info.size))
	assert(#info.fields == 2, "the layout carries " .. #info.fields .. " fields")
	for _, field in ipairs(info.fields) do
		local want = header[field.name]
		assert(want ~= nil, "unexpected field " .. field.name)
		assert(field.offset == want.offset and field.size == want.size,
			("%s at offset %d, size %d"):format(field.name, field.offset, field.size))
	end
end)

test("linux.tls carries no name the cipher and size tables already hold", function()
	assert(ltls["CIPHER_AES_GCM_128"] == nil, "CIPHER_AES_GCM_128 is present")
	assert(ltls["CIPHER_AES_GCM_128_KEY_SIZE"] == nil, "CIPHER_AES_GCM_128_KEY_SIZE is present")
end)

