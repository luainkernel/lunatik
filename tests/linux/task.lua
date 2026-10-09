--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.task test (see run.sh).
--

local task  = require("linux.task")
local test  = require("tests.lib").test
local check = require("tests.linux.check")

-- the states of <linux/sched.h>, beside its bounds and TASK_COMM_LEN, which share their prefix
local states = {
	"RUNNING", "INTERRUPTIBLE", "UNINTERRUPTIBLE", "PARKED", "DEAD", "WAKEKILL", "WAKING", "NOLOAD", "NEW",
	"RTLOCK_WAIT", "FREEZABLE", "FROZEN", "ANY", "FREEZABLE_UNSAFE", "KILLABLE", "STOPPED", "TRACED", "IDLE",
	"NORMAL", "REPORT", "REPORT_IDLE",
}

test("linux.task carries the task states and nothing else", function()
	check.holds("task", task, states)
end)

