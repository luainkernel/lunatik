--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe aggregate test (see aggregate.sh).

local probe  = require("probe")
local systab = require("syscall.table")

local target = systab["personality"]

local function first()
	print("probe aggregate: first")
end

local function second()
	print("probe aggregate: second")
end

probe.new(target, {pre = first})
probe.new(target, {pre = second})

