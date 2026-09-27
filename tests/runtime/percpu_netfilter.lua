--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu netfilter test (see percpu_netfilter.sh).

local netfilter = require("netfilter")
local nfcount   = require("tests.runtime.nfcount")

netfilter.register(nfcount.localin(nfcount.count, nfcount.MARK))

