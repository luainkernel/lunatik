--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the bpf queue map test (see run.sh).

local map = require("bpf").map
local bpf = require("linux.bpf")
local test = require("util").test

local path = "/sys/fs/bpf/test_map_queue"

local function drain(m)
	while m:pop() do
	end
end

test("bpf.map queue push and peek returns inserted value", function()
	local m = map(path)
	assert(m:push("foo"))
	local value = m:peek()
	assert(value == "foo", "expected 'foo', got: " .. tostring(value))
	m:close()
end)

test("bpf.map queue peek does not remove value", function()
	local m = map(path)
	drain(m)
	assert(m:push("foo"))
	assert(m:peek() == "foo")
	assert(m:peek() == "foo")
	m:close()
end)

test("bpf.map queue pop removes values in FIFO order", function()
	local m = map(path)
	drain(m)
	assert(m:push("foo"))
	assert(m:push("bar"))
	assert(m:push("baz"))
	assert(m:pop() == "foo", "expected first pushed value")
	assert(m:pop() == "bar", "expected second pushed value")
	assert(m:pop() == "baz", "expected third pushed value")
	m:close()
end)

test("bpf.map queue pop on empty queue returns nil", function()
	local m = map(path)
	drain(m)
	assert(m:pop() == nil, "expected nil from empty queue")
	m:close()
end)

test("bpf.map queue peek on empty queue returns nil", function()
	local m = map(path)
	drain(m)
	assert(m:peek() == nil, "expected nil from empty queue")
	m:close()
end)

test("bpf.map queue push full queue returns false", function()
	local m = map(path)
	drain(m)
	for i = 1, #m do
		assert(m:push("xyz"))
	end
	assert(m:push("ovr") == false, "expected false when queue is full")
	m:close()
end)

test("bpf.map queue push BPF_EXIST overwrites the oldest when full", function()
	local m = map(path)
	drain(m)
	assert(m:push("aaa"))
	for i = 2, #m do
		assert(m:push("bbb"))
	end
	assert(m:push("ccc", bpf.EXIST))
	local value = m:pop()
	assert(value == "bbb", "expected oldest 'aaa' dropped, got: " .. tostring(value))
	drain(m)
	m:close()
end)

test("bpf.map queue push NOEXIST raises", function()
	local m = map(path)
	drain(m)
	assert(not pcall(m.push, m, "xyz", bpf.NOEXIST), "expected error: NOEXIST is not a push flag")
	m:close()
end)

test("bpf.map queue lookup returns nil", function()
	local m = map(path)
	assert(m:lookup("") == nil, "expected nil: queue lookup unsupported")
	m:close()
end)

test("bpf.map queue update raises", function()
	local m = map(path)
	assert(not pcall(m.update, m, "", "foo", bpf.ANY), "expected error: queue does not support update")
	m:close()
end)

test("bpf.map queue delete raises", function()
	local m = map(path)
	assert(not pcall(m.delete, m, ""), "expected error: queue does not support delete")
	m:close()
end)

test("bpf.map queue remove raises", function()
	local m = map(path)
	assert(not pcall(m.remove, m, ""), "expected error: queue does not support remove")
	m:close()
end)

test("bpf.map queue next raises", function()
	local m = map(path)
	assert(not pcall(m.next, m), "expected error: queue does not support iteration")
	m:close()
end)

test("bpf.map queue info reports map properties", function()
	local m = map(path)
	local info = m:info()
	assert(info.type == bpf.MAP_TYPE_QUEUE, "expected queue map type")
	assert(info.key_size == 0, "expected key_size 0")
	assert(info.value_size == 3, "expected value_size 3")
	assert(info.max_entries == 128, "expected max_entries 128")
	assert(#m == 128, "expected #m == max_entries")
	m:close()
end)

