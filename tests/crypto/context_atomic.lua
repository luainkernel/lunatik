--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Atomic-context body for the crypto context test (see context.sh).

local crypto = require("crypto")
local insert = table.insert

local ATTEMPTS <const> = 16
local REFUSAL  <const> = "'crypto%.%l+': process%-context class in interrupt%-context runtime"

local constructors = {
	{name = "sha256", new = crypto.shash},
	{name = "ecdsa-nist-p256", new = crypto.sig},
	{name = "lz4", new = crypto.acompress},
}
if crypto.comp then -- the binding has no comp from 6.15 on
	insert(constructors, {name = "lz4", new = crypto.comp})
end

local function refuse()
	for _ = 1, ATTEMPTS do
		for _, constructor in ipairs(constructors) do
			local ok, err = pcall(constructor.new, constructor.name)
			assert(not ok, "crypto served an interrupt-context runtime: " .. constructor.name)
			assert(err:match(REFUSAL), "crypto raised something else: " .. err)
		end
	end
end

return refuse

