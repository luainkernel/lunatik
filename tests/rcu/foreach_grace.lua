--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Kernel-side script for the rcu.foreach grace period test (see foreach_grace.sh).

local rcu   = require("rcu")
local data  = require("data")
local linux = require("linux")
local test  = require("util").test

local keys = {"a", "b", "c"}
local NAP_MS <const> = 100

test("rcu.foreach walks on after a grace period the callback let pass", function()
	local t = rcu.table(1)
	for _, k in ipairs(keys) do
		t[k] = data.new(8)
	end
	local visits = 0
	rcu.foreach(t, function(k, v)
		visits = visits + 1
		v:getint64(0)
		for _, o in ipairs(keys) do
			if o ~= k then
				t[o] = nil
			end
		end
		linux.schedule(NAP_MS)
	end)
	assert(visits == 1, "expected 1 visit, got " .. visits)
end)

