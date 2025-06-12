-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only

--- Lua entry point for the Linux Kernel Crypto API compression module.
-- Provides consistent access to compression objects.
--
-- @classmod crypto.comp
-- @usage
--   local comp = require("crypto_comp")
--   local compressor = comp.new("lz4")
-- @see crypto_comp

return require("crypto_comp")
