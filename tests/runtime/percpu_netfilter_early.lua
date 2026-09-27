--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu netfilter test, a packet during creation (see percpu_netfilter.sh).

local netfilter = require("netfilter")
local nfcount   = require("tests.runtime.nfcount")

local SPIN <const> = 100000000

netfilter.register(nfcount.localin(nfcount.count, nfcount.MARK))

print("percpu netfilter early: armed")

for _ = 1, SPIN do end -- widen the gap between arming the hook and publishing this runtime

