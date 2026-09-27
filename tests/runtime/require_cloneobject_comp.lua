--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The crypto_comp case of the require_cloneobject test (see require_cloneobject.sh).

local crypto = require("crypto")
local check  = require("tests.runtime.check")

check.clones(crypto.comp("lz4"))

