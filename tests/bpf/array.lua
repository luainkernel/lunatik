--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the bpf array map test (see run.sh).

local array = require("bpf").array
local bpf = require("linux.bpf")
local test = require("util").test
local pack = string.pack

local path = "/sys/fs/bpf/test_map_array"

test("bpf.array update and lookup by index", function()
	local m = array(path)
	local key = pack("I4", 1)
	assert(m:update(key, pack("I4", 42)))
	local value = m:lookup(key)
	assert(value == pack("I4", 42), "expected packed 42")
	m:close()
end)

test("bpf.array lookup in range never misses", function()
	local m = array(path)
	assert(m:lookup(pack("I4", 3)) == pack("I4", 0), "expected zero-filled value for an unwritten index")
	m:close()
end)

test("bpf.array lookup out of range returns nil", function()
	local m = array(path)
	assert(m:lookup(pack("I4", 100)) == nil, "expected nil past max_entries")
	m:close()
end)

test("bpf.array update out of range raises", function()
	local m = array(path)
	assert(not pcall(m.update, m, pack("I4", 100), pack("I4", 0)), "expected error past max_entries")
	m:close()
end)

test("bpf.array update NOEXIST returns false", function()
	local m = array(path)
	assert(m:update(pack("I4", 0), pack("I4", 7), bpf.NOEXIST) == false, "array elements always exist")
	m:close()
end)

test("bpf.array delete raises", function()
	local m = array(path)
	assert(not pcall(m.delete, m, pack("I4", 0)), "expected error: arrays do not support delete")
	m:close()
end)

test("bpf.array remove raises", function()
	local m = array(path)
	assert(not pcall(m.remove, m, pack("I4", 0)), "expected error: arrays do not support lookup-and-delete")
	m:close()
end)

test("bpf.array next iterates all indexes", function()
	local m = array(path)
	assert(m:info().type == bpf.MAP_TYPE_ARRAY, "expected array map type")
	local count = 0
	for _ in m.next, m do
		count = count + 1
		assert(count <= #m, "iterated past max_entries")
	end
	assert(count == #m, "expected all " .. #m .. " indexes, counted: " .. count)
	m:close()
end)

test("bpf.array rejects other map types", function()
	assert(not pcall(array, "/sys/fs/bpf/test_map"), "expected error on hash map")
	assert(not pcall(array, "/sys/fs/bpf/test_map_stack"), "expected error on stack map")
end)

