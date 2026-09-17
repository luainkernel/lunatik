--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side callback for the trampoline benchmark: the least a callback can do
-- (see tools/bench/xdp.sh).

local xdp    = require("xdp")
local action = require("linux.xdp")

local PASS <const> = action.PASS

local function bench_verdict(ctx)
	ctx:action(PASS)
end

xdp.attach(bench_verdict)

