--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local new = require("crypto.skcipher").new
local util = require("util")
local bin2hex = util.bin2hex
local hex2bin = util.hex2bin

local test, expected, result

xpcall(
  function ()
    print"SKCIPHER AES-128-CBC"
    local c = new"cbc(aes)"
    local plaintext = "This is a test!!" -- 16 bytes - must be a multiple of block size for CBC without explicit padding

    c:setkey"0123456789abcdef"

    test = "AES-128-CBC encrypt"
    expected = hex2bin"d05e07d91a4b4cd10951f8cf195f27b5"
    result = c:encrypt("fedcba9876543210", plaintext)
    assert(result == expected, "Ciphertext mismatch")

    test = "AES-128-CBC decrypt"
    expected = plaintext
    result = c:decrypt("fedcba9876543210", result)
    assert(result == expected, "Decryption mismatch")

    print("All SKCIPHER tests passed!")

  end,

  function(msg)
    print("Test " .. test .. " FAILED")
    print("Result:   " .. bin2hex(result))
    print("Expected: " .. bin2hex(expected))
    print(msg)
    print(debug.traceback())
  end
)
