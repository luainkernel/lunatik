--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- The reader of tests/rcu/object_grace.sh: reads one key, by index and through foreach, while the writer replaces it.

local lunatik = require("lunatik")
local rcu     = require("rcu")
local runner  = require("lunatik.runner")
local thread  = require("thread")
local pace    = require("tests.rcu.pace")

local WRITER <const> = "tests/rcu/object_grace_writer"
local KEY <const> = "slot"
local RUN_MS <const> = 10000

local function touch(_, d)
	d:getint64(0)
end

local function read(grace)
	local d = grace[KEY]
	rcu.foreach(grace, touch)
	return d ~= nil and d:getint64(0) or nil
end

return function()
	lunatik._ENV.grace = rcu.table(16)
	runner.spawn(WRITER)

	local grace = lunatik._ENV.grace
	local deadline = pace.milliseconds() + RUN_MS
	local last, seen = nil, 0
	while not thread.shouldstop() and pace.milliseconds() < deadline do
		local ok, n = pcall(read, grace)
		if not ok then
			print("object_grace: " .. tostring(n))
			break
		end
		if n ~= nil and n ~= last then
			last, seen = n, seen + 1
		end
		pace.yield()
	end
	if seen < 2 then
		print("object_grace: the reader saw " .. seen .. " objects, never one replaced")
	end

	lunatik._ENV.grace = nil
end

