--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the bpf hash map test (see run.sh).

local map = require("bpf").map
local bpf = require("linux.bpf")
local test = require("util").test

local path = "/sys/fs/bpf/test_map"
local percpu_path = "/sys/fs/bpf/test_map_percpu"

test("bpf.map lookup returns inserted value", function()
	local m = map(path)
	local value = m:lookup("foo")
	assert(value == "bar", "expected 'bar', got: " .. tostring(value))
	m:close()
end)

test("bpf.map update inserts value", function()
	local m = map(path)
	assert(m:update("abc", "xyz", bpf.ANY))
	local value = m:lookup("abc")
	assert(value == "xyz", "expected 'xyz', got: " .. tostring(value))
	m:close()
end)

test("bpf.map delete removes value", function()
	local m = map(path)
	assert(m:update("tmp", "val", bpf.ANY))
	assert(m:delete("tmp"))
	local value = m:lookup("tmp")
	assert(value == nil, "expected nil after delete")
	m:close()
end)

test("bpf.map lookup missing key returns nil", function()
	local m = map(path)
	local value = m:lookup("zzz")
	assert(value == nil, "expected nil")
	m:close()
end)

test("bpf.map delete missing key returns false", function()
	local m = map(path)
	assert(m:delete("zzz") == false, "expected false for missing key")
	m:close()
end)

test("bpf.map update flag condition not met returns false", function()
	local m = map(path)
	assert(m:update("dup", "one", bpf.ANY))
	assert(m:update("dup", "two", bpf.NOEXIST) == false, "expected false on NOEXIST for existing key")
	assert(m:update("zzz", "two", bpf.EXIST) == false, "expected false on EXIST for missing key")
	m:close()
end)

test("bpf.map update invalid flag raises", function()
	local m = map(path)
	assert(not pcall(m.update, m, "flg", "val", 99), "expected error on invalid flag")
	m:close()
end)

test("bpf.map remove extracts and removes value", function()
	local m = map(path)
	assert(m:update("del", "pop", bpf.ANY))
	local value = m:remove("del")
	assert(value == "pop", "expected 'pop', got: " .. tostring(value))
	local missing = m:lookup("del")
	assert(missing == nil, "expected nil lookup after remove")
	m:close()
end)

test("bpf.map remove missing key returns nil", function()
	local m = map(path)
	local value = m:remove("zzz")
	assert(value == nil, "expected nil for non-existent key extraction")
	m:close()
end)

test("bpf.map next fetches first key when passed nil", function()
	local m = map(path)
	assert(m:update("k11", "v11", bpf.ANY))
	local first_key = m:next()
	assert(first_key ~= nil, "expected a key string, got nil")
	m:close()
end)

test("bpf.map next drives a generic for", function()
	local m = map(path)
	assert(m:update("k21", "v21", bpf.ANY))
	assert(m:update("k22", "v22", bpf.ANY))
	local seen = {}
	local count = 0
	for key in m.next, m do
		count = count + 1
		seen[key] = true
		assert(count <= 128, "iterated past max_entries")
	end
	assert(seen["k21"] and seen["k22"], "expected inserted keys in iteration")
	m:close()
end)

test("bpf.map invalid sizes raise", function()
	local m = map(path)
	assert(not pcall(m.lookup, m, "toolong"), "expected error on oversized key")
	assert(not pcall(m.next, m, ""), "expected error on empty key")
	assert(not pcall(m.update, m, "key", "oversized"), "expected error on oversized value")
	m:close()
end)

test("bpf.map info and length report the map properties", function()
	local m = map(path)
	local info = m:info()
	assert(info.type == bpf.MAP_TYPE_HASH, "expected hash map type")
	assert(info.key_size == 3, "expected key_size 3")
	assert(info.value_size == 3, "expected value_size 3")
	assert(info.max_entries == 128, "expected max_entries 128")
	assert(#m == 128, "expected #m == max_entries")
	m:close()
end)

test("bpf.map methods raise after close", function()
	local m = map(path)
	m:close()
	assert(not pcall(m.lookup, m, "foo"), "expected error after close")
end)

test("bpf.map open rejects non-map path", function()
	assert(not pcall(map, "/dev/null"), "expected error on non-bpf path")
	assert(not pcall(map, "/nonexistent"), "expected error on missing path")
end)

test("bpf.map open rejects unsupported map type", function()
	assert(not pcall(map, percpu_path), "expected error on percpu map")
end)

