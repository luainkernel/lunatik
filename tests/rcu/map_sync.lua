--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Usage:
-- > lunatik spawn tests/rcu/map_sync
--
-- It should output a random number about every second.
--
-- To stop it:
-- > lunatik stop tests/rcu/map_sync ; lunatik stop tests/rcu/map_sync_clean

local lunatik = require "lunatik"
local linux = require "linux"
local rcu = require "rcu"
local runner = require "lunatik.runner"
local thread = require "thread"

local function milliseconds()
	return linux.time() / 1000000
end

return function()
	lunatik._ENV.whitelist = rcu.table(1024)
	runner.spawn "tests/rcu/map_sync_clean"

	local whitelist = lunatik._ENV.whitelist
	local start = milliseconds()
	local last_print = start
	local now = start

	while (not thread.shouldstop()) and (now - start < 60000) do
		now = milliseconds()
		local entry = whitelist[now - linux.random(1, 1000)]

		if entry and now - last_print > 1000 then
			last_print = now
			print(string.format("map_sync: reader found entry written %dms ago", now - entry:getnumber(0)))
		end
	end

	lunatik._ENV.whitelist = nil
end

