--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Cases described in tests/README.md (rcu/index_whole): an index matches the whole key.

local rcu  = require("rcu")
local test = require("util").test

test("rcu.table reads nil for a prefix of a key in the same bucket", function()
	local t = rcu.table(1)
	t.abc = 1
	assert(t.ab == nil, "a prefix read " .. tostring(t.ab))
	assert(t.abc == 1, "the key read " .. tostring(t.abc))
end)

test("rcu.table adds an entry for a prefix of a key instead of replacing it", function()
	local t = rcu.table(1)
	t.abc = 1
	t.ab = 2
	assert(t.abc == 1, "the key read " .. tostring(t.abc))
	assert(t.ab == 2, "the prefix read " .. tostring(t.ab))
end)

test("rcu.table reads nil for the empty key until it is set", function()
	local t = rcu.table(1)
	t.abc = 1
	assert(t[""] == nil, "the empty key read " .. tostring(t[""]))
	t[""] = 2
	assert(t[""] == 2, "the empty key read " .. tostring(t[""]))
	assert(t.abc == 1, "the key read " .. tostring(t.abc))
end)

test("rcu.table tells keys apart past an embedded NUL", function()
	local t = rcu.table(1)
	t["a\0b"] = 3
	assert(t["a\0c"] == nil, "a key differing past the NUL read " .. tostring(t["a\0c"]))
	assert(t.a == nil, "the key's head read " .. tostring(t.a))
	assert(t["a\0b"] == 3, "the key read " .. tostring(t["a\0b"]))
end)

