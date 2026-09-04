--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local sched = require("sched")
local scx   = require("linux.scx")

local DEFAULT <const> = 0

local function workload(ctx)
	local ok, err = pcall(function()
		ctx:dsq(DEFAULT)
		ctx:slice(scx.SLICE_DFL)
	end)

	if ok then
		print("sched pass test pass: task class assigned")
	else
		print("sched pass test fail: " .. tostring(err))
	end
end

sched.attach(workload)

