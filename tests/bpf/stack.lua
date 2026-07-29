--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the bpf stack map test (see run.sh).

local map = require("bpf").map
local bpf = require("linux.bpf")
local test = require("util").test

local path = "/sys/fs/bpf/test_map_stack"

local function drain(m)
	while m:pop() do
	end
end

test("bpf.map stack push and peek returns inserted value", function()
	local m = map(path)
	assert(m:push("foo"))
	local value = m:peek()
	assert(value == "foo", "expected 'foo', got: " .. tostring(value))
	drain(m)
	m:close()
end)

test("bpf.map stack peek does not remove value", function()
	local m = map(path)
	drain(m)
	assert(m:push("foo"))
	assert(m:peek() == "foo")
	assert(m:peek() == "foo")
	drain(m)
	m:close()
end)

test("bpf.map stack pop removes values in LIFO order", function()
	local m = map(path)
	drain(m)
	assert(m:push("foo"))
	assert(m:push("bar"))
	assert(m:push("baz"))
	assert(m:pop() == "baz", "expected last pushed value")
	assert(m:pop() == "bar", "expected second pushed value")
	assert(m:pop() == "foo", "expected first pushed value")
	m:close()
end)

test("bpf.map stack pop on empty stack returns nil", function()
	local m = map(path)
	drain(m)
	assert(m:pop() == nil, "expected nil from empty stack")
	m:close()
end)

test("bpf.map stack peek on empty stack returns nil", function()
	local m = map(path)
	drain(m)
	assert(m:peek() == nil, "expected nil from empty stack")
	m:close()
end)

test("bpf.map stack push full stack returns false", function()
	local m = map(path)
	drain(m)
	for i = 1, #m do
		assert(m:push("abc"))
	end
	assert(m:push("abc") == false, "expected false when stack is full")
	m:close()
end)

test("bpf.map stack push BPF_EXIST overwrites the bottom when full", function()
	local m = map(path)
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

test("bpf.map stack push NOEXIST raises", function()
	local m = map(path)
	drain(m)
	assert(not pcall(m.push, m, "abc", bpf.NOEXIST), "expected error: NOEXIST is not a push flag")
	m:close()
end)

test("bpf.map stack lookup returns nil", function()
	local m = map(path)
	assert(m:lookup("") == nil, "expected nil: stack lookup unsupported")
	m:close()
end)

test("bpf.map stack update raises", function()
	local m = map(path)
	assert(not pcall(m.update, m, "", "foo", bpf.ANY), "expected error: stack does not support update")
	m:close()
end)

test("bpf.map stack delete raises", function()
	local m = map(path)
	assert(not pcall(m.delete, m, ""), "expected error: stack does not support delete")
	m:close()
end)

test("bpf.map stack remove raises", function()
	local m = map(path)
	assert(not pcall(m.remove, m, ""), "expected error: stack does not support remove")
	m:close()
end)

test("bpf.map stack next raises", function()
	local m = map(path)
	assert(not pcall(m.next, m), "expected error: stack does not support iteration")
	m:close()
end)

test("bpf.map stack info reports map properties", function()
	local m = map(path)
	local info = m:info()
	assert(info.type == bpf.MAP_TYPE_STACK, "expected stack map type")
	assert(info.key_size == 0, "expected key_size 0")
	assert(info.value_size == 3, "expected value_size 3")
	assert(info.max_entries == 128, "expected max_entries 128")
	assert(#m == 128, "expected #m == max_entries")
	m:close()
end)

