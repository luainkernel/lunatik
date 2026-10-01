--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the sched pass test (see run.sh).

local sched = require("sched")
local scx   = require("linux.scx")

local DSQ_DEFAULT <const> = 0

local reported = false

local function workload(ctx)
	if not reported then
		reported = true
		print("sched pass test pass: task class assigned")
	end
	return DSQ_DEFAULT, scx.SLICE_DFL
end

sched.attach(workload)

