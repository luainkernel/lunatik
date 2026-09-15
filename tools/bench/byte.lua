--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side callback for the trampoline benchmark: one packet byte read before
-- the verdict (see tools/bench/xdp.sh).

local xdp    = require("xdp")
local action = require("linux.xdp")

local PASS <const> = action.PASS
local DROP <const> = action.DROP

local function bench_byte(ctx)
	local octet = ctx:packet():getbyte(0) -- bit 0 of the destination MAC is the multicast bit
	ctx:action((octet & 1) == 0 and PASS or DROP)
end

xdp.attach(bench_byte)

