--
-- SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik = require "lunatik"
local linux = require "linux"
local rcu = require "rcu"
local data = require "data"
local thread = require "thread"

local function milliseconds()
	return linux.time() / 1000000
end

return function()
	local whitelist = lunatik._ENV.whitelist
	local start = milliseconds()
	local now = start

	while (not thread.shouldstop()) and (now - start < 60000) do
		now = milliseconds()
		local d = whitelist[now] or data.new(32)
		d:setnumber(0, now)
		whitelist[now] = d

		rcu.map(whitelist, function(k, v)
			if now > v:getnumber(0) + 500 then
				whitelist[k] = nil
			end
		end)
	end

end

