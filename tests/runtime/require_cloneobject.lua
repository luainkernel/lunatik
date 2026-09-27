--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the require_cloneobject test (see require_cloneobject.sh).

local crypto = require("crypto")
local data   = require("data")
local set    = require("set")
local check  = require("tests.runtime.check")

check.clones(data.new(4), "softirq")
check.clones(set.labeled({key = 1}))
check.clones(crypto.shash("sha256"))
check.clones(crypto.skcipher("cbc(aes)"))
check.clones(crypto.aead("gcm(aes)"))
check.clones(crypto.rng("stdrng"))

