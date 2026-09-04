--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the sched re-attach test (see run.sh).

local sched = require("sched")

local function replaced(ctx)
end

local function current(ctx)
end

sched.attach(replaced)
sched.attach(current)
sched.detach()

