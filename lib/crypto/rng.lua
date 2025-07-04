--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- RNG (Random Number Generation) operations.
-- This module provides a Lua wrapper for RNG operations,
-- using the underlying 'crypto_rng' C module.
--
-- @classmod crypto.rng
-- @see crypto_rng

return require("crypto_rng")

