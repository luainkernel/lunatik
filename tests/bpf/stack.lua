--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the bpf stack map test (see run.sh).

local stack = require("bpf").stack
local bpf = require("linux.bpf")
local test = require("util").test

local path = "/sys/fs/bpf/test_map_stack"

local function drain(m)
	while m:pop() do
	end
end

test("bpf.stack push and peek returns inserted value", function()
	local m = stack(path)
	assert(m:push("foo"))
	local value = m:peek()
	assert(value == "foo", "expected 'foo', got: " .. tostring(value))
	drain(m)
	m:close()
end)

test("bpf.stack peek does not remove value", function()
	local m = stack(path)
	drain(m)
	assert(m:push("foo"))
	assert(m:peek() == "foo")
	assert(m:peek() == "foo")
	drain(m)
	m:close()
end)

test("bpf.stack pop removes values in LIFO order", function()
	local m = stack(path)
	drain(m)
	assert(m:push("foo"))
	assert(m:push("bar"))
	assert(m:push("baz"))
	assert(m:pop() == "baz", "expected last pushed value")
	assert(m:pop() == "bar", "expected second pushed value")
	assert(m:pop() == "foo", "expected first pushed value")
	m:close()
end)

test("bpf.stack pop on empty stack returns nil", function()
	local m = stack(path)
	drain(m)
	assert(m:pop() == nil, "expected nil from empty stack")
	m:close()
end)

test("bpf.stack peek on empty stack returns nil", function()
	local m = stack(path)
	drain(m)
	assert(m:peek() == nil, "expected nil from empty stack")
	m:close()
end)

test("bpf.stack push full stack returns false", function()
	local m = stack(path)
	drain(m)
	for i = 1, #m do
		assert(m:push("abc"))
	end
	assert(m:push("abc") == false, "expected false when stack is full")
	m:close()
end)

test("bpf.stack push BPF_EXIST overwrites the bottom when full", function()
	local m = stack(path)
	drain(m)
	assert(m:push("aaa"))
	for i = 2, #m do
		assert(m:push("bbb"))
	end
	assert(m:push("ccc", bpf.EXIST))
	assert(m:pop() == "ccc", "expected the new value on top")
	for i = 2, #m do
		assert(m:pop() == "bbb", "expected bottom 'aaa' dropped")
	end
	assert(m:pop() == nil, "expected empty stack")
	m:close()
end)

test("bpf.stack push NOEXIST raises", function()
	local m = stack(path)
	drain(m)
	assert(not pcall(m.push, m, "abc", bpf.NOEXIST), "expected error: NOEXIST is not a push flag")
	m:close()
end)

test("bpf.stack handle has no key-value operations", function()
	local m = stack(path)
	assert(m.lookup == nil and m.update == nil and m.delete == nil and m.remove == nil and m.next == nil,
		"expected no key-value methods on a stack handle")
	m:close()
end)

test("bpf.stack rejects other map types", function()
	assert(not pcall(stack, "/sys/fs/bpf/test_map"), "expected error on hash map")
	assert(not pcall(stack, "/sys/fs/bpf/test_map_queue"), "expected error on queue map")
end)

test("bpf.stack info reports map properties", function()
	local m = stack(path)
	local info = m:info()
	assert(info.type == bpf.MAP_TYPE_STACK, "expected stack map type")
	assert(info.key_size == 0, "expected key_size 0")
	assert(info.value_size == 3, "expected value_size 3")
	assert(info.max_entries == 128, "expected max_entries 128")
	assert(#m == 128, "expected #m == max_entries")
	m:close()
end)

