--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the bpf queue map test (see run.sh).

local queue = require("bpf").queue
local bpf = require("linux.bpf")
local test = require("util").test

local path = "/sys/fs/bpf/test_map_queue"

local function drain(m)
	while m:pop() do
	end
end

test("bpf.queue push and peek returns inserted value", function()
	local m = queue(path)
	assert(m:push("foo"))
	local value = m:peek()
	assert(value == "foo", "expected 'foo', got: " .. tostring(value))
	m:close()
end)

test("bpf.queue peek does not remove value", function()
	local m = queue(path)
	drain(m)
	assert(m:push("foo"))
	assert(m:peek() == "foo")
	assert(m:peek() == "foo")
	m:close()
end)

test("bpf.queue pop removes values in FIFO order", function()
	local m = queue(path)
	drain(m)
	assert(m:push("foo"))
	assert(m:push("bar"))
	assert(m:push("baz"))
	assert(m:pop() == "foo", "expected first pushed value")
	assert(m:pop() == "bar", "expected second pushed value")
	assert(m:pop() == "baz", "expected third pushed value")
	m:close()
end)

test("bpf.queue pop on empty queue returns nil", function()
	local m = queue(path)
	drain(m)
	assert(m:pop() == nil, "expected nil from empty queue")
	m:close()
end)

test("bpf.queue peek on empty queue returns nil", function()
	local m = queue(path)
	drain(m)
	assert(m:peek() == nil, "expected nil from empty queue")
	m:close()
end)

test("bpf.queue push full queue returns false", function()
	local m = queue(path)
	drain(m)
	for i = 1, #m do
		assert(m:push("xyz"))
	end
	assert(m:push("ovr") == false, "expected false when queue is full")
	m:close()
end)

test("bpf.queue push BPF_EXIST overwrites the oldest when full", function()
	local m = queue(path)
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

test("bpf.queue push NOEXIST raises", function()
	local m = queue(path)
	drain(m)
	assert(not pcall(m.push, m, "xyz", bpf.NOEXIST), "expected error: NOEXIST is not a push flag")
	m:close()
end)

test("bpf.queue handle has no key-value operations", function()
	local m = queue(path)
	assert(m.lookup == nil and m.update == nil and m.delete == nil and m.remove == nil and m.next == nil,
		"expected no key-value methods on a queue handle")
	m:close()
end)

test("bpf.queue rejects other map types", function()
	assert(not pcall(queue, "/sys/fs/bpf/test_map"), "expected error on hash map")
	assert(not pcall(queue, "/sys/fs/bpf/test_map_stack"), "expected error on stack map")
end)

test("bpf.queue info reports map properties", function()
	local m = queue(path)
	local info = m:info()
	assert(info.type == bpf.MAP_TYPE_QUEUE, "expected queue map type")
	assert(info.key_size == 0, "expected key_size 0")
	assert(info.value_size == 3, "expected value_size 3")
	assert(info.max_entries == 128, "expected max_entries 128")
	assert(#m == 128, "expected #m == max_entries")
	m:close()
end)

