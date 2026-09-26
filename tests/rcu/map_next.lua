--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Kernel-side script for the rcu.map walk test (see run.sh).

local rcu   = require("rcu")
local data  = require("data")
local test  = require("util").test

local insert = table.insert

local keys = {"a", "b", "c"}
local MAXKEY <const> = 256 -- LUARCU_MAXKEY, LUAL_BUFFERSIZE as lunatik_conf.h sets it

local function onebucket(value)
	local t = rcu.table(1)
	for _, k in ipairs(keys) do
		t[k] = value
	end
	return t
end

local function others(k)
	local rest = {}
	for _, o in ipairs(keys) do
		if o ~= k then
			insert(rest, o)
		end
	end
	return rest
end

test("rcu.map does not visit an entry the callback removed", function()
	local t = onebucket(1)
	local visited = {}
	rcu.map(t, function(k)
		insert(visited, k)
		for _, o in ipairs(others(k)) do
			t[o] = nil
		end
	end)
	assert(#visited == 1, "expected 1 visit, got " .. #visited)
end)

test("rcu.map visits the value the callback put in place of an entry", function()
	local t = onebucket(1)
	local seen = {}
	rcu.map(t, function(k, v)
		insert(seen, v)
		for _, o in ipairs(others(k)) do
			t[o] = 2
		end
	end)
	assert(#seen == 3, "expected 3 visits, got " .. #seen)
	for i = 2, #seen do
		assert(seen[i] == 2, "visit " .. i .. " saw " .. seen[i] .. ", not the replacement")
	end
end)

test("rcu.map does not visit an entry the callback added to the bucket it is walking", function()
	local t = onebucket(1)
	local visits = 0
	rcu.map(t, function(k)
		visits = visits + 1
		t[k .. "z"] = 1
	end)
	assert(visits == 3, "expected 3 visits, got " .. visits)
end)

test("rcu.map visits nothing on an empty table and one entry among empty buckets", function()
	local t = rcu.table(16)
	local visits = 0
	rcu.map(t, function()
		visits = visits + 1
	end)
	assert(visits == 0, "an empty table should be visited 0 times, got " .. visits)
	t.only = 1
	rcu.map(t, function()
		visits = visits + 1
	end)
	assert(visits == 1, "one entry should be visited once, got " .. visits)
end)

test("rcu.map hands the callback a key whole past an embedded NUL", function()
	local t = rcu.table(1)
	t["a\0b"] = 3
	t.a = 1
	local seen = {}
	rcu.map(t, function(k, v)
		seen[k] = v
	end)
	assert(seen["a\0b"] == 3 and seen.a == 1, "the keys should reach the callback whole")
end)

test("rcu.map hands the callback the empty key and the longest key whole", function()
	local t = rcu.table(1)
	local longest = ("k"):rep(MAXKEY - 1)
	t[""] = 1
	t[longest] = 2
	local seen = {}
	rcu.map(t, function(k, v)
		seen[k] = v
	end)
	assert(seen[""] == 1, "the empty key read " .. tostring(seen[""]))
	assert(seen[longest] == 2, "the longest key read " .. tostring(seen[longest]))
end)

test("rcu.map raises what the callback raises and visits nothing after it", function()
	local t = onebucket(1)
	local visits = 0
	local ok, err = pcall(rcu.map, t, function()
		visits = visits + 1
		error("boom")
	end)
	assert(not ok, "rcu.map swallowed the callback's error")
	assert(err:match("boom"), "rcu.map raised something else: " .. err)
	assert(visits == 1, "expected 1 visit, got " .. visits)
end)

test("rcu.map keeps a table nothing else holds through the walk", function()
	local held = setmetatable({}, {__mode = "v"})
	held[1] = onebucket(1)
	local visits = 0
	rcu.map(held[1], function()
		visits = visits + 1
		collectgarbage()
		assert(held[1] ~= nil, "the table was collected under the walk")
	end)
	assert(visits == 3, "expected 3 visits, got " .. visits)
end)

