--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Kernel-side script for the rcu.map walk test (see run.sh).

local rcu  = require("rcu")
local test = require("util").test

local insert = table.insert

local keys = {"a", "b", "c"}

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
	local visits = 0
	rcu.map(t, function(k)
		visits = visits + 1
		for _, o in ipairs(others(k)) do
			t[o] = nil
		end
	end)
	assert(visits == 1, "expected 1 visit, got " .. visits)
end)

test("rcu.map never hands the callback a value an entry lost under the walk", function()
	local t = onebucket(1)
	local visits = {}
	rcu.map(t, function(k, v)
		for _, visit in ipairs(visits) do
			assert(visit.key ~= k, "visited " .. k .. " twice")
		end
		insert(visits, {key = k, value = v})
		for _, o in ipairs(others(k)) do
			t[o] = 2
		end
	end)
	assert(#visits >= 1 and #visits <= 3, "expected 1 to 3 visits, got " .. #visits)
	assert(visits[1].value == 1, "the first visit saw " .. tostring(visits[1].value))
	for i = 2, #visits do
		assert(visits[i].value == 2, "visit " .. i .. " saw the value " .. visits[i].key .. " lost")
	end
end)

test("rcu.map does not visit an entry the callback added to its bucket", function()
	local t = onebucket(1)
	local visits = 0
	rcu.map(t, function()
		visits = visits + 1
		t.d = 1
	end)
	assert(visits == 3, "expected 3 visits, got " .. visits)
end)

test("rcu.map hands the callback a key with an embedded NUL whole", function()
	local t = rcu.table(1)
	local key = "a\0b"
	t[key] = 1
	local seen
	rcu.map(t, function(k)
		seen = k
	end)
	assert(seen == key, "expected the whole key, got " .. string.format("%q", tostring(seen)))
end)

test("rcu.map raises the callback's error with no visit after it", function()
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

