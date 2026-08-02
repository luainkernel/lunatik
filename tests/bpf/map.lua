--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the bpf.map layer test (see run.sh).

local map = require("bpf.map")
local struct = require("struct")
local bpf = require("linux.bpf")
local test = require("util").test

local tbl_path   = "/sys/fs/bpf/test_map_tbl"
local map_path   = "/sys/fs/bpf/test_map"
local array_path = "/sys/fs/bpf/test_map_array"
local lru_path   = "/sys/fs/bpf/test_map_lru"
local queue_path = "/sys/fs/bpf/test_map_queue"
local stack_path = "/sys/fs/bpf/test_map_stack"

local function drain(m)
	while m:pop() do
	end
end

test("bpf.map hash scalar integer round-trip", function()
	local t <close> = map.hash(tbl_path, "I4", "I4")
	t[1] = 42
	assert(t[1] == 42, "expected 42, got: " .. tostring(t[1]))
	t[1] = nil
	assert(t[1] == nil, "expected nil after delete")
end)

test("bpf.map hash byte-string keys read the seeded map", function()
	local t <close> = map.hash(map_path, "c3", "c3")
	assert(t.foo == "bar", "expected seeded 'bar', got: " .. tostring(t.foo))
	assert(t.zzz == nil, "expected nil for missing key")
end)

test("bpf.map function-named keys are plain map keys", function()
	local t <close> = map.hash(tbl_path, "c4", "I4")
	t.info = 7
	t.clos = 9
	assert(t.info == 7, "expected 7, got: " .. tostring(t.info))
	assert(t.clos == 9, "expected 9, got: " .. tostring(t.clos))
	t.info = nil
	t.clos = nil
	assert(t.info == nil, "expected nil after delete")
end)

test("bpf.map nil delete of missing key is a no-op", function()
	local t <close> = map.hash(tbl_path, "I4", "I4")
	t[99] = nil
end)

test("bpf.map multi-value format uses arrays", function()
	local t <close> = map.hash(tbl_path, "I4", "I2I2")
	t[2] = {258, 772}
	local v = t[2]
	assert(v[1] == 258 and v[2] == 772, "expected {258, 772}")
	t[2] = nil
end)

test("bpf.map struct codec value", function()
	local codec = struct({size = 4, fields = {{name = "v", offset = 0, size = 4}}})
	local t <close> = map.hash(tbl_path, "I4", codec)
	t[3] = {42}
	local v = t[3]
	assert(v[1] == 42, "expected {42}")
	t[3] = nil
end)

test("bpf.map pairs iterates decoded entries", function()
	local t <close> = map.hash(tbl_path, "I4", "I4")
	t[10] = 100
	t[20] = 200
	local seen = {}
	for k, v in pairs(t) do
		seen[k] = v
	end
	assert(seen[10] == 100 and seen[20] == 200, "expected decoded pairs")
	t[10] = nil
	t[20] = nil
end)

test("bpf.map array indexes by position", function()
	local t <close> = map.array(array_path, "I4", "I4")
	t[0] = 11
	assert(t[0] == 11, "expected 11, got: " .. tostring(t[0]))
	t[0] = 0
end)

test("bpf.map lru_hash round-trip", function()
	local t <close> = map.lru_hash(lru_path, "c3", "c3")
	t.abc = "xyz"
	assert(t.abc == "xyz", "expected 'xyz', got: " .. tostring(t.abc))
	t.abc = nil
	assert(t.abc == nil, "expected nil after delete")
end)

test("bpf.map rejects mismatched specs", function()
	assert(not pcall(map.hash, tbl_path, "I2", "I4"), "expected key size mismatch error")
	assert(not pcall(map.hash, tbl_path, "I4", "I8"), "expected value size mismatch error")
	assert(not pcall(map.hash, tbl_path, "I4"), "expected invalid value spec error")
	assert(not pcall(map.hash, tbl_path, "I4", {}), "expected invalid table spec error")
	assert(not pcall(map.queue, queue_path, "I4"), "expected value size mismatch error")
end)

test("bpf.map rejects other map types", function()
	assert(not pcall(map.hash, queue_path, "I4", "c3"), "expected error on queue map")
	assert(not pcall(map.queue, tbl_path, "I4"), "expected error on hash map")
end)

test("bpf.map functions raise after close", function()
	local t = map.hash(tbl_path, "I4", "I4")
	map.close(t)
	assert(not pcall(map.info, t), "expected error after close")
end)

test("bpf.map closes the proxy on scope exit", function()
	local escaped
	do
		local t <close> = map.hash(tbl_path, "I4", "I4")
		escaped = t
	end
	assert(not pcall(map.info, escaped), "expected the proxy to be closed on scope exit")
end)

test("bpf.map queue pops in FIFO order", function()
	local q <close> = map.queue(queue_path, "c3")
	drain(q)
	assert(q:push("foo"))
	assert(q:push("bar"))
	assert(q:pop() == "foo", "expected first pushed value")
	assert(q:pop() == "bar", "expected second pushed value")
end)

test("bpf.map stack pops in LIFO order", function()
	local s <close> = map.stack(stack_path, "c3")
	drain(s)
	assert(s:push("foo"))
	assert(s:push("bar"))
	assert(s:pop() == "bar", "expected last pushed value")
	assert(s:pop() == "foo", "expected first pushed value")
end)

test("bpf.map queue peek does not remove the value", function()
	local q <close> = map.queue(queue_path, "c3")
	drain(q)
	assert(q:push("foo"))
	assert(q:peek() == "foo")
	assert(q:peek() == "foo")
	drain(q)
end)

test("bpf.map queue pop and peek on empty return nil", function()
	local q <close> = map.queue(queue_path, "c3")
	drain(q)
	assert(q:pop() == nil, "expected nil from empty queue")
	assert(q:peek() == nil, "expected nil from empty queue")
end)

test("bpf.map queue push on a full map returns false", function()
	local q <close> = map.queue(queue_path, "c3")
	drain(q)
	for _ = 1, q:info().max_entries do
		assert(q:push("xyz"))
	end
	assert(q:push("ovr") == false, "expected false when the map is full")
	drain(q)
end)

test("bpf.map queue values follow the spec", function()
	local q <close> = map.queue(queue_path, "I1I2")
	drain(q)
	assert(q:push({7, 258}))
	local v = q:pop()
	assert(v[1] == 7 and v[2] == 258, "expected {7, 258}")
end)

test("bpf.map queue info reports map properties", function()
	local q <close> = map.queue(queue_path, "c3")
	local info = q:info()
	assert(info.type == bpf.MAP_TYPE_QUEUE, "expected queue map type")
	assert(info.value_size == 3, "expected value_size 3")
	assert(info.max_entries == 128, "expected max_entries 128")
end)

test("bpf.map queue methods raise after close", function()
	local q = map.queue(queue_path, "c3")
	q:close()
	assert(not pcall(q.info, q), "expected error after close")
end)

test("bpf.map closes the queue object on scope exit", function()
	local escaped
	do
		local q <close> = map.queue(queue_path, "c3")
		escaped = q
	end
	assert(not pcall(escaped.info, escaped), "expected the object to be closed on scope exit")
end)

