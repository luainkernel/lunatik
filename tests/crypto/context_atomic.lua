--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Atomic-context body for the crypto context test (see context.sh).

local crypto = require("crypto")

local ATTEMPTS <const> = 16
local ARMED    <const> = "not allowed once the runtime is armed"
local CLASS    <const> = "'crypto%.%l+': process%-context class in interrupt%-context runtime"

-- each constructor and the refusal it raises past the body of a softirq runtime
local constructors = {
	sha256 = {new = crypto.shash, refusal = ARMED},
	["ctr(aes)"] = {new = crypto.skcipher, refusal = ARMED},
	["ecdsa-nist-p256"] = {new = crypto.sig, refusal = CLASS},
}
if crypto.comp then -- the binding has no comp from 6.15 on
	constructors.lz4 = {new = crypto.comp, refusal = CLASS}
end

local function refuse()
	for _ = 1, ATTEMPTS do
		for algname, constructor in pairs(constructors) do
			local ok, err = pcall(constructor.new, algname)
			assert(not ok, "crypto served an interrupt-context runtime: " .. algname)
			assert(err:match(constructor.refusal), "crypto raised something else: " .. err)
		end
	end
end

return refuse

