--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu probe test, a probe after load (see percpu_probe.sh).

local probe  = require("probe")
local systab = require("syscall.table")

local reported = false

local function nop() end

local function probe_late()
	if reported then
		return
	end
	reported = true
	local ok, err = pcall(probe.new, systab["personality"], {pre = nop})
	print("percpu probe late: " .. (ok and "registered" or err:gsub("^.-:%d+: ", "")))
end

probe.new(systab["personality"], {pre = probe_late})

