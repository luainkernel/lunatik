--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu probe test, a target the kernel refuses (see percpu_probe.sh).

local probe  = require("probe")
local systab = require("syscall.table")

local UNKNOWN <const> = "lunatik_no_such_symbol"

local function nop() end

probe.new(systab["personality"], {pre = nop})

print("percpu probe unknown: one target armed")

probe.new(UNKNOWN, {pre = nop})

