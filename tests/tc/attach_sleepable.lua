--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc verdict test (see test_tc.sh).

local tc = require("tc")

local ok, err = pcall(tc.attach, function() end)
assert(not ok, "attach accepted a sleepable runtime")
assert(err:match("runtime context mismatch"), "unexpected error: " .. tostring(err))

