--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the scx unsupported test (see run.sh).

local scx = require("scx")

local ok, err = pcall(scx.attach, function() end)
assert(not ok, "attach accepted a kernel without sched_ext")
assert(err == "EOPNOTSUPP", "unexpected error: " .. tostring(err))
assert(select("#", scx.detach()) == 0, "detach answered a kernel without sched_ext")

