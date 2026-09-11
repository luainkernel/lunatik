--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu probe test (see percpu_probe.sh).

local lunatik = require("lunatik")
local probe   = require("probe")
local systab  = require("syscall.table")

local LIMIT <const> = 16

local target = systab["personality"]

local cpu = lunatik.cpu() or "plain"
local hits = 0

local function count(address)
	if address ~= target then -- the handler is handed the address the script gave, not the one the kernel resolved
		return
	end
	hits = hits + 1
	if hits <= LIMIT then
		print("percpu probe: cpu " .. tostring(cpu))
	end
end

probe.new(target, {pre = count})

