--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the bpf hash map test (see run.sh).

local hash = require("bpf").hash
local bpf = require("linux.bpf")
local test = require("tests.lib").test
local pinned = require("tests.bpf.pinned")

local pack = string.pack

local path = "/sys/fs/bpf/test_map"
local percpu_path = "/sys/fs/bpf/test_map_percpu"
local full_path = "/sys/fs/bpf/test_map_full"

test("bpf.hash lookup returns inserted value", function()
	local m = hash(path)
	local value = m:lookup("foo")
	assert(value == "bar", "expected 'bar', got: " .. tostring(value))
	m:close()
end)

test("bpf.hash update inserts value", function()
	local m = hash(path)
	assert(m:update("abc", "xyz", bpf.update.ANY))
	local value = m:lookup("abc")
	assert(value == "xyz", "expected 'xyz', got: " .. tostring(value))
	m:close()
end)

test("bpf.hash delete removes value", function()
	local m = hash(path)
	assert(m:update("tmp", "val", bpf.update.ANY))
	assert(m:delete("tmp"))
	local value = m:lookup("tmp")
	assert(value == nil, "expected nil after delete")
	m:close()
end)

test("bpf.hash lookup missing key returns nil", function()
	local m = hash(path)
	local value = m:lookup("zzz")
	assert(value == nil, "expected nil")
	m:close()
end)

test("bpf.hash delete missing key returns false", function()
	local m = hash(path)
	assert(m:delete("zzz") == false, "expected false for missing key")
	m:close()
end)

test("bpf.hash update flag condition not met returns false", function()
	local m = hash(path)
	assert(m:update("dup", "one", bpf.update.ANY))
	assert(m:update("dup", "two", bpf.update.NOEXIST) == false, "expected false on NOEXIST for existing key")
	assert(m:update("zzz", "two", bpf.update.EXIST) == false, "expected false on EXIST for missing key")
	m:close()
end)

test("bpf.hash update flag condition met succeeds", function()
	local m = hash(path)
	m:delete("flg")
	assert(m:update("flg", "one", bpf.update.NOEXIST), "expected insert on NOEXIST for missing key")
	assert(m:update("flg", "two", bpf.update.EXIST), "expected overwrite on EXIST for existing key")
	assert(m:lookup("flg") == "two", "expected 'two', got: " .. tostring(m:lookup("flg")))
	m:delete("flg")
	m:close()
end)

test("bpf.hash update of a new key on a full map returns false", function()
	local m = hash(full_path)
	local entries = m:info().max_entries
	local beyond = pack("I4", entries + 1)
	for i = 1, entries do
		assert(m:update(pack("I4", i), pack("I4", i)), "expected an insert below max_entries")
	end
	assert(m:update(beyond, pack("I4", 0)) == false, "expected false on a full map")
	assert(m:update(pack("I4", 1), pack("I4", 0)), "expected an overwrite of a present key on a full map")
	assert(m:delete(pack("I4", 1)))
	assert(m:update(beyond, pack("I4", 0)), "expected an insert once a delete made room")
	pinned.clear(m)
	m:close()
end)

test("bpf.hash update invalid flag raises", function()
	local m = hash(path)
	assert(not pcall(m.update, m, "flg", "val", 99), "expected error on invalid flag")
	m:close()
end)

test("bpf.hash remove extracts and removes value", function()
	local m = hash(path)
	assert(m:update("del", "pop", bpf.update.ANY))
	local value = m:remove("del")
	assert(value == "pop", "expected 'pop', got: " .. tostring(value))
	local missing = m:lookup("del")
	assert(missing == nil, "expected nil lookup after remove")
	m:close()
end)

test("bpf.hash remove missing key returns nil", function()
	local m = hash(path)
	local value = m:remove("zzz")
	assert(value == nil, "expected nil for non-existent key extraction")
	m:close()
end)

test("bpf.hash next fetches first key when passed nil", function()
	local m = hash(path)
	assert(m:update("k11", "v11", bpf.update.ANY))
	local first_key = m:next()
	assert(first_key ~= nil, "expected a key string, got nil")
	m:close()
end)

test("bpf.hash next drives a generic for", function()
	local m = hash(path)
	assert(m:update("k21", "v21", bpf.update.ANY))
	assert(m:update("k22", "v22", bpf.update.ANY))
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

test("bpf.hash invalid sizes raise", function()
	local m = hash(path)
	assert(not pcall(m.lookup, m, "toolong"), "expected error on oversized key")
	assert(not pcall(m.next, m, ""), "expected error on empty key")
	assert(not pcall(m.update, m, "key", "oversized"), "expected error on oversized value")
	m:close()
end)

test("bpf.hash info reports the map properties", function()
	local m = hash(path)
	pinned.checkinfo(m, bpf.map_type.HASH, 3)
	m:close()
end)

test("bpf.hash names its class and refuses another", function()
	local m = hash(path)
	pinned.checkclass(m, "bpf.hash")
	m:close()
end)

test("bpf.hash handle has no queue operations", function()
	local m = hash(path)
	assert(m.push == nil and m.pop == nil and m.peek == nil, "expected no queue methods on a key-value handle")
	m:close()
end)

test("bpf.hash rejects other map types", function()
	assert(not pcall(hash, "/sys/fs/bpf/test_map_array"), "expected error on array map")
	assert(not pcall(hash, "/sys/fs/bpf/test_map_lru"), "expected error on LRU hash map")
	assert(not pcall(hash, "/sys/fs/bpf/test_map_queue"), "expected error on queue map")
	assert(not pcall(hash, "/sys/fs/bpf/test_map_stack"), "expected error on stack map")
end)

test("bpf.hash methods raise after close", function()
	local m = hash(path)
	m:close()
	assert(not pcall(m.lookup, m, "foo"), "expected error after close")
end)

test("bpf.hash open rejects non-map path", function()
	assert(not pcall(hash, "/dev/null"), "expected error on non-bpf path")
	assert(not pcall(hash, "/nonexistent"), "expected error on missing path")
end)

test("bpf.hash open rejects unsupported map type", function()
	assert(not pcall(hash, percpu_path), "expected error on percpu map")
end)

