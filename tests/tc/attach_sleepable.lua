--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict test (see test_tc.sh).

local tc = require("tc")

local MISMATCH <const> = "runtime context mismatch: tc.ctx needs softirq"

local ok, err = pcall(tc.attach, function() end)
assert(not ok, "attach accepted a sleepable runtime")
assert(err:find(MISMATCH, 1, true), "unexpected error: " .. tostring(err))

