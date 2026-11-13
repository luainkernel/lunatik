--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto irqsoff test (see irqsoff.sh).

local hid    = require("hid")
local crypto = require("crypto")
local lib    = require("tests.lib")

local raises = lib.raises

local IRQS    <const> = "not allowed with IRQs disabled"
local KEY     <const> = "0123456789abcdef"
local COUNTER <const> = "fedcba9876543210"
local DATA    <const> = "irqsoff"
local EPROTO  <const> = 71

-- allocated before the driver, so irqsoff.sh skips the test where the kernel lacks one
local shash    = lib.alloc(crypto.shash, "sha256")
local skcipher = lib.alloc(crypto.skcipher, "ctr(aes)")
skcipher:setkey(KEY) -- so that encrypt, unrefused, would reach the cipher

-- drops the report with EPROTO, which irqsoff.sh reads back, only where each method refused
local function raw_event()
	raises(IRQS, shash.digest, shash, DATA)
	raises(IRQS, skcipher.setkey, skcipher, KEY)
	raises(IRQS, skcipher.encrypt, skcipher, COUNTER, DATA)
	return -EPROTO
end

hid.register({
	name = "lunatik_crypto_irqsoff",
	id_table = {{bus = 0x06, vendor = 0xf055, product = 0x2379}}, -- BUS_VIRTUAL, irqsoff.c's device alone
	raw_event = raw_event,
})

