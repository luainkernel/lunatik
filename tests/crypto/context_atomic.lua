--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Atomic-context body for the crypto context test (see context.sh).

local crypto = require("crypto")

local ATTEMPTS <const> = 16

local constructors = {sha256 = crypto.shash}
if crypto.comp then -- the binding has no comp from 6.15 on
	constructors.lz4 = crypto.comp
end

local function refuse()
	for _ = 1, ATTEMPTS do
		for algname, new in pairs(constructors) do
			local ok, err = pcall(new, algname)
			assert(not ok, "crypto served an interrupt-context runtime: " .. algname)
			assert(err:match("interrupt%-context runtime"), "crypto raised something else: " .. err)
		end
	end
end

return refuse

