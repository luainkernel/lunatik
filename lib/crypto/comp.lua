--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Compatibility wrapper for the legacy `crypto.comp` API.
-- On kernels < 6.15 this returns the native `crypto.comp` constructor; on
-- newer kernels, where the synchronous crypto_comp API was removed, it falls
-- back to `crypto.compress` (built on top of `crypto.acompress`), which
-- exposes the same interface: `("lz4")`, `:compress(data, max_len)` and
-- `:decompress(data, max_len)`.
-- @classmod crypto.comp

local crypto = require("crypto")

return crypto.comp or require("crypto.compress").new
