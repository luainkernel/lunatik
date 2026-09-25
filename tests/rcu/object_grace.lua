--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- The reader of tests/rcu/object_grace.sh: reads one key, by index and through map, while the writer replaces it.

local lunatik = require("lunatik")
local rcu     = require("rcu")
local runner  = require("lunatik.runner")
local thread  = require("thread")
local linux   = require("linux")

local WRITER <const> = "tests/rcu/object_grace_writer"
local KEY <const> = "slot"
local RUN_MS <const> = 10000

local function milliseconds()
	return linux.time() // 1000000
end

local function touch(_, d)
	d:getnumber(0)
end

local function read(grace)
	local d = grace[KEY]
	rcu.map(grace, touch)
	return d ~= nil and d:getnumber(0) or nil
end

return function()
	lunatik._ENV.grace = rcu.table(16)
	runner.spawn(WRITER)

	local grace = lunatik._ENV.grace
	local deadline = milliseconds() + RUN_MS
	local last, seen = nil, 0
	while not thread.shouldstop() and milliseconds() < deadline do
		local ok, n = pcall(read, grace)
		if not ok then
			print("object_grace: " .. tostring(n))
			break
		end
		if n ~= nil and n ~= last then
			last, seen = n, seen + 1
		end
	end
	if seen < 2 then
		print("object_grace: the reader saw " .. seen .. " objects, never one replaced")
	end

	lunatik._ENV.grace = nil
end

