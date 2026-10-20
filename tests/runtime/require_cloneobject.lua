--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the require_cloneobject test (see require_cloneobject.sh).

local crypto = require("crypto")
local data   = require("data")
local set    = require("set")
local check  = require("tests.runtime.check")
local alloc  = require("tests.lib").alloc

-- allocated before any clone runs, so require_cloneobject.sh skips the case where the kernel lacks one
local shash    = alloc(crypto.shash, "sha256")
local skcipher = alloc(crypto.skcipher, "cbc(aes)")
local aead     = alloc(crypto.aead, "gcm(aes)")
local rng      = alloc(crypto.rng, "stdrng")

check.clones(data.new(4), "softirq")
check.clones(set.new({key = 1}))
check.clones(shash)
check.clones(skcipher)
check.clones(aead)
check.clones(rng)

