--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local sched = require("sched")

local REALTIME <const> = 0
local BATCH <const>    = 1

local policy = {
	{ pattern = "^nginx", dsq = REALTIME, slice = 1000000 }, -- 1ms
	{ pattern = "^firefox", dsq = BATCH, slice = 10000000 }, -- 10ms
}

local function log(command, dsq, slice)
	print(string.format("workload: [%s]: %d %d", command, dsq, slice))
end

local function workload(ctx)
	local task = ctx:task()
	local comm = task:comm()
	for _, rule in ipairs(policy) do
		if comm:match(rule.pattern) then
			ctx:dsq(rule.dsq)
			ctx:slice(rule.slice)
			log(comm, rule.dsq, rule.slice)
			return
		end
	end
end

sched.attach(workload)

