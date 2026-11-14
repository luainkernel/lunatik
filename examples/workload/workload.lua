--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local scx = require("scx")

local REALTIME <const> = 0
local BATCH <const>    = 1
local DEFAULT <const>  = 2
local MSEC <const>     = 1000000

local policy = {
	{ pattern = "^nginx", dsq = REALTIME, slice = MSEC },
	{ pattern = "^firefox", dsq = BATCH, slice = 10 * MSEC },
}

local function workload(ctx)
	local task = ctx:task()
	local comm = task:comm()
	for _, rule in ipairs(policy) do
		if comm:match(rule.pattern) then
			return rule.dsq, rule.slice
		end
	end
	return DEFAULT
end

scx.attach(workload)

