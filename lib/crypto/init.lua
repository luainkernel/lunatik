--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Wrapper for the Linux Kernel Crypto API.
--
-- This module provides a simplified interface to the underlying `crypto_*`
-- C modules. It allows for a more natural and convenient API, such as
-- using `require("crypto").shash()` instead of `require("crypto_shash").new()`.
--
-- @module crypto

local crypto_shash = require("crypto_shash")

local crypto = {}

--- Creates a new SHASH (synchronous hash) object.
-- This function is a convenient alias for `require("crypto_shash").new()`.
-- It instantiates a hash object for a specific algorithm.
-- @function crypto.shash
-- @tparam string algname The name of the hash algorithm (e.g., "sha256", "hmac(sha256)").
-- @treturn crypto_shash The new SHASH object.
-- @raise Error if the algorithm is not found or if allocation fails.
-- @usage
--   local crypto = require("crypto")
--   local hasher = crypto.shash("sha256")
--   local digest = hasher:digest("hello world")
crypto.shash = crypto_shash.new

return crypto

