--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Compression operations.
-- This module provides a Lua wrapper for compression operations,
-- using the underlying 'crypto_comp' C module.
--
-- @classmod crypto.comp
-- @see crypto_comp

return require("crypto_comp")

