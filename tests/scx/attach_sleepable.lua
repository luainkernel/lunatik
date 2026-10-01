--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the scx attach guard test (see run.sh).

local scx = require("scx")

local MISMATCH <const> = "runtime context mismatch: scx.ctx needs hardirq"

local ok, err = pcall(scx.attach, function() end)
assert(not ok, "attach accepted a sleepable runtime")
assert(err:find(MISMATCH, 1, true), "unexpected error: " .. tostring(err))

