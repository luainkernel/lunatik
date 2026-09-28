--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik = require "lunatik"
local rcu = require "rcu"
local data = require "data"
local thread = require "thread"
local pace = require("tests.rcu.pace")

return function()
	local whitelist = lunatik._ENV.whitelist
	local start = pace.milliseconds()
	local now = start

	while (not thread.shouldstop()) and (now - start < 60000) do
		now = pace.milliseconds()
		local d = whitelist[now] or data.new(32)
		d:setint64(0, now)
		whitelist[now] = d

		rcu.map(whitelist, function(k, v)
			if now > v:getint64(0) + 500 then
				whitelist[k] = nil
			end
		end)

		pace.yield()
	end

end

