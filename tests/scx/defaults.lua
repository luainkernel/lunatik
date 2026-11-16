--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the scx defaults test (see run.sh).

local ext = require("linux.scx")

-- the values linux/sched/ext.h gives
local GLOBAL    <const> = 0x8000000000000001
local SLICE_DFL <const> = 20000000

assert(ext.dsq.GLOBAL == GLOBAL, "linux.scx.dsq.GLOBAL is " .. tostring(ext.dsq.GLOBAL))
assert(ext.slice.DFL == SLICE_DFL, "linux.scx.slice.DFL is " .. tostring(ext.slice.DFL))

