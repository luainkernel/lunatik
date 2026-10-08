--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the scx pass test (see run.sh).

local scx = require("scx")
local ext = require("linux.scx")

local DSQ_DEFAULT <const> = 0

local reported = false

local function workload()
	if not reported then
		reported = true
		print("scx pass test pass: task class assigned")
	end
	return DSQ_DEFAULT, ext.SLICE_DFL
end

scx.attach(workload)

