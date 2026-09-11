--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu probe test, a call during creation (see percpu_probe.sh).

local lunatik = require("lunatik")
local probe   = require("probe")
local systab  = require("syscall.table")

local SPIN <const> = 100000000

local cpu = lunatik.cpu()

local function count()
	print("percpu probe early: cpu " .. tostring(cpu))
end

probe.new(systab["personality"], {pre = count})

print("percpu probe early: armed")

for _ = 1, SPIN do end -- widen the gap between arming the kprobe and publishing this runtime

