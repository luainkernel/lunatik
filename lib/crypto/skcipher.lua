--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- SKCipher (Symmetric Key Cipher) operations.
-- This module provides a Lua wrapper for SKCipher operations,
-- using the underlying 'crypto_skcipher' C module.
--
-- @classmod crypto.skcipher
-- @see crypto_skcipher

return require("crypto_skcipher")

