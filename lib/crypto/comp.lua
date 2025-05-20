-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only

-- Simply re-export the C module, ensuring consistency in api
-- by allowing `require"crypto.comp"`.
return require("crypto_comp")

