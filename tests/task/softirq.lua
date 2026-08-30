--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the task softirq guard test (see run.sh).
-- luatask_class is opened with LUNATIK_OPT_SOFTIRQ, so `task` must load in
-- a softirq-flagged runtime, and task.current() must allocate its object
-- with the class's opt correctly OR'd in (GFP_ATOMIC), without crashing
-- the kernel.
--

local task = require("task")

local t = task.current()
assert(t ~= nil, "current() returned nil in softirq runtime")
assert(type(t:pid()) == "number", "pid() failed in softirq runtime")
assert(type(t:comm()) == "string", "comm() failed in softirq runtime")

print("task: usable in softirq runtime")

