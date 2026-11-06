--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Hardirq runtime for the crypto hardirq test (see run.sh).

local crypto = require("crypto")

local HARDIRQ <const> = "not allowed in a hardirq runtime"
local IRQS    <const> = "not allowed with IRQs disabled"

local function refused(expected, what, fn, ...)
	local ok, err = pcall(fn, ...)
	assert(not ok, "a hardirq runtime ran " .. what)
	assert(err:find(expected, 1, true), what .. " raised something else: " .. tostring(err))
end

local function construct(when)
	refused(HARDIRQ, "crypto.shash " .. when, crypto.shash, "sha256")
	refused(HARDIRQ, "crypto.skcipher " .. when, crypto.skcipher, "ctr(aes)")
end

construct("in its body")

local function handed(shash, skcipher)
	construct("past its body")
	refused(IRQS, "a crypto.shash method", shash.algname, shash)
	refused(IRQS, "a crypto.skcipher method", skcipher.algname, skcipher)
end

return handed

