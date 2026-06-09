--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local sched = require("sched")
local scx   = require("linux.scx")

local REALTIME = 0
local BATCH = 1
local DEFAULT = 2

local policy = {
	{ pattern = "^nginx", dsq = REALTIME, slice = 1000000 }, -- 1ms
	{ pattern = "^firefox", dsq = BATCH, slice = 10000000 }, -- 10ms
}

local function log(command, dsq, slice)
	print(string.format("workload: [%s]: %d %d", command, dsq, slice))
end

local function workload(ctx)
	local task = ctx:task()
	for _, rule in ipairs(policy) do
		if task:comm():match(rule.pattern) then
			ctx:dsq(rule.dsq)
			ctx:slice_ns(rule.slice)
			log(task:comm(), rule.dsq, rule.slice)
			return
		end
	end
	ctx:dsq(DEFAULT)
	ctx:slice_ns(scx.SLICE_DFL)
end

sched.attach(workload)

