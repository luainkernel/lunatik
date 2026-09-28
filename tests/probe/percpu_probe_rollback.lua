--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu probe test, a set that fails partway (see percpu_probe.sh).

local lunatik = require("lunatik")
local cpu     = require("cpu")
local probe   = require("probe")
local systab  = require("syscall.table")

local function nop() end

probe.new(systab["personality"], {pre = nop})

if lunatik.cpu() == cpu.maxid() then
	error("percpu probe rollback: refusing the last runtime")
end

