--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the sched attach guard test (see run.sh).

local sched = require("sched")

local ok, err = pcall(sched.attach, function() end)
assert(not ok, "attach accepted a sleepable runtime")
assert(err:match("runtime context mismatch"), "unexpected error: " .. tostring(err))

