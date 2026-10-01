--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the xdp verdict test (see test_xdp.sh).

local xdp = require("xdp")

local MISMATCH <const> = "runtime context mismatch: xdp.ctx needs softirq"

local ok, err = pcall(xdp.attach, function() end)
assert(not ok, "attach accepted a sleepable runtime")
assert(err:find(MISMATCH, 1, true), "unexpected error: " .. tostring(err))

