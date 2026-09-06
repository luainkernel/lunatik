--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu probe test, duplicate registration (see percpu_probe.sh).

local probe  = require("probe")
local systab = require("syscall.table")

local function nop() end

probe.new(systab["personality"], {pre = nop})
probe.new(systab["personality"], {pre = nop})

