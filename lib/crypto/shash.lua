--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- shash (Secure Hash) operations.
-- This module provides a Lua wrapper for shash operations,
-- which are used for computing cryptographic hash functions
-- such as SHA-1, SHA-256, etc.
-- using the underlying 'crypto_shash' C module.
--
-- @classmod crypto.shash
-- @see crypto_shash

return require("crypto_shash")

