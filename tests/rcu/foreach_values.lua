--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local rcu = require "rcu"
local data = require "data"
local test = require("tests.lib").test

test("rcu.foreach iterates boolean values", function()
	local t = rcu.table(4)
	t["yes"] = true
	t["no"] = false
	local results = {}
	rcu.foreach(t, function(k, v) results[k] = v end)
	assert(results["yes"] == true, "expected true, got: " .. tostring(results["yes"]))
	assert(results["no"] == false, "expected false, got: " .. tostring(results["no"]))
end)

test("rcu.foreach iterates integer values", function()
	local t = rcu.table(4)
	t["a"] = 42
	t["b"] = -7
	local results = {}
	rcu.foreach(t, function(k, v) results[k] = v end)
	assert(results["a"] == 42, "expected 42, got: " .. tostring(results["a"]))
	assert(results["b"] == -7, "expected -7, got: " .. tostring(results["b"]))
end)

test("rcu.foreach iterates userdata values (regression)", function()
	local t = rcu.table(4)
	local d = data.new(8)
	d:setint64(0, 99)
	t["obj"] = d
	local found = false
	rcu.foreach(t, function(k, v)
		if k == "obj" then
			assert(v:getint64(0) == 99, "wrong value in userdata")
			found = true
		end
	end)
	assert(found, "userdata entry not found by rcu.foreach")
end)

test("rcu.foreach iterates mixed types", function()
	local t = rcu.table(4)
	t["flag"] = true
	t["count"] = 42
	local d = data.new(4)
	t["obj"] = d
	local count = 0
	rcu.foreach(t, function(k, v) count = count + 1 end)
	assert(count == 3, "expected 3 entries, got: " .. count)
end)

test("rcu.foreach skips nil (deleted) entries", function()
	local t = rcu.table(4)
	t["x"] = 1
	t["y"] = 2
	t["x"] = nil  -- delete
	local count = 0
	rcu.foreach(t, function(k, v) count = count + 1 end)
	assert(count == 1, "expected 1 entry after deletion, got: " .. count)
end)

