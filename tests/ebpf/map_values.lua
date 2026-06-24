--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local map = require "ebpf.map"
local bpf = require "linux.bpf"
local test = require("util").test

test("ebpf.map lookup returns inserted value", function()
	local test = map.open("/sys/fs/bpf/test_map")
	local value = test:lookup("foo")
	assert(value == "bar", "expected 'bar', got: " .. tostring(value))
	test:close()
end)

test("ebpf.map update inserts value", function()
	local test = map.open("/sys/fs/bpf/test_map")
	assert(test:update("abc", "xyz", bpf.ANY))
	local value = test:lookup("abc")
	assert(value == "xyz", "expected 'xyz', got: " .. tostring(value))
	test:close()
end)

test("ebpf.map delete removes value", function()
	local test = map.open("/sys/fs/bpf/test_map")
	assert(test:update("tmp", "val", bpf.ANY))
	assert(test:delete("tmp"))
	local value = test:lookup("tmp")
	assert(value == nil, "expected nil after delete")
	test:close()
end)

test("ebpf.map lookup missing key returns nil", function()
	local test = map.open("/sys/fs/bpf/test_map")
	local value = test:lookup("zzz")
	assert(value == nil, "expected nil")
	test:close()
end)

test("ebpf.map remove extracts and removes value", function()
    local test = map.open("/sys/fs/bpf/test_map")
    assert(test:update("del", "pop", bpf.ANY))
    local value = test:remove("del")
    assert(value == "pop", "expected 'pop', got: " .. tostring(value))
    local missing = test:lookup("del")
    assert(missing == nil, "expected nil lookup after remove")
    test:close()
end)

test("ebpf.map remove missing key returns nil", function()
    local test = map.open("/sys/fs/bpf/test_map")
    local value = test:remove("zzz")
    assert(value == nil, "expected nil for non-existent key extraction")
    test:close()
end)

test("ebpf.map get_next_key fetches first key when passed nil", function()
    local test = map.open("/sys/fs/bpf/test_map")
    assert(test:update("k11", "v11", bpf.ANY))
    local first_key = test:get_next_key()
    assert(first_key ~= nil, "expected a key string, got nil")
    test:close()
end)

test("ebpf.map get_next_key can iterate through elements", function()
    local test = map.open("/sys/fs/bpf/test_map")
    assert(test:update("k21", "v21", bpf.ANY))
    assert(test:update("k22", "v22", bpf.ANY))
    local key = test:get_next_key()
    local count = 0
    while key do
        count = count + 1
        key = test:get_next_key(key)
        if count > 100 then break end
    end
    assert(count >= 2, "expected to iterate through at least 2 elements, counted: " .. count)
    test:close()
end)

