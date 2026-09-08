--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto context test (see context.sh).

local lunatik = require("lunatik")
local test    = require("util").test

local SCRIPT <const> = "tests/crypto/context_atomic"

test("crypto.shash refuses an interrupt-context runtime", function()
	local runtime <close> = lunatik.runtime(SCRIPT, "softirq")
	runtime:resume()
end)

