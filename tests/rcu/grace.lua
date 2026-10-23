--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- The reader and writer loops of object_grace and string_grace (see object_grace.sh and string_grace.sh).

local lunatik = require("lunatik")
local rcu     = require("rcu")
local runner  = require("lunatik.runner")
local thread  = require("thread")
local pace    = require("tests.rcu.pace")

local KEY    <const> = "slot"
local RUN_MS <const> = 10000

local grace = {}

-- read(shared, key) answers the number of the value it read, or nil; a raise, or no replacement seen, is printed after tag
function grace.read(tag, writer, read)
	lunatik._ENV.grace = rcu.table(16)
	runner.spawn(writer)

	local shared = lunatik._ENV.grace
	local deadline = pace.milliseconds() + RUN_MS
	local last, seen = nil, 0
	while not thread.shouldstop() and pace.milliseconds() < deadline do
		local ok, n = pcall(read, shared, KEY)
		if not ok then
			print(tag .. ": " .. tostring(n))
			break
		end
		if n ~= nil and n ~= last then
			last, seen = n, seen + 1
		end
		pace.yield()
	end
	if seen < 2 then
		print(tag .. ": the reader saw " .. seen .. " values, never one replaced")
	end

	lunatik._ENV.grace = nil
end

-- new(n) answers the value numbered n
function grace.write(new)
	local shared = lunatik._ENV.grace
	local deadline = pace.milliseconds() + RUN_MS
	local n = 0
	while not thread.shouldstop() and pace.milliseconds() < deadline do
		n = n + 1
		shared[KEY] = new(n)
		pace.yield()
	end
	shared[KEY] = nil
end

return grace

