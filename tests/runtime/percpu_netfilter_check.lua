--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu netfilter test, the count (see percpu_netfilter.sh).

local lunatik = require("lunatik")
local rcu     = require("rcu")
local test    = require("util").test

local PREFIX <const> = "nf_percpu:"
local COUNT  <const> = 5

local env = lunatik._ENV

test("the marked requests were counted once, by one instance", function()
	local counted = {}
	rcu.map(env, function (key, count)
		if key:sub(1, #PREFIX) == PREFIX then
			table.insert(counted, key)
			print("percpu netfilter: " .. key .. " " .. count)
			assert(count == COUNT, key .. " counted " .. count .. " of " .. COUNT)
		end
	end)
	assert(#counted == 1, #counted .. " instances counted")
	env[counted[1]] = nil
end)

