--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Atomic-context body for the crypto context test (see context.sh).

local crypto = require("crypto")

local ATTEMPTS <const> = 16

local function refuse()
	for _ = 1, ATTEMPTS do
		local ok, err = pcall(crypto.shash, "sha256")
		assert(not ok, "crypto.shash served an interrupt-context runtime")
		assert(err:match("interrupt%-context runtime"), "crypto.shash raised something else: " .. err)
	end
end

return refuse

