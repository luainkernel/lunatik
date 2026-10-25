--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Kernel-side script for the rcu.table string values test (see run.sh).

local lunatik = require("lunatik")
local rcu     = require("rcu")
local data    = require("data")
local test    = require("tests.lib").test

local RECEIVER <const> = "tests/rcu/strings_recv"
local KEY      <const> = "tests.rcu.strings"
local REPLY    <const> = "reply"
local LONG     <const> = 100000  -- past a page
local HUGE     <const> = 1 << 23 -- past KMALLOC_MAX_SIZE on 4K pages, so the writer's allocator vmallocs it

local values = {"text", "", "a\0b", string.rep("x", LONG)}

local function same(read, value)
	return type(value) == "userdata" and type(read) == "userdata" or read == value
end

local function cross(context)
	lunatik._ENV[KEY] = string.rep("s", HUGE)
	local runtime <close> = lunatik.runtime(RECEIVER, context)
	runtime:resume()
	local reply = lunatik._ENV[KEY]
	lunatik._ENV[KEY] = nil
	assert(reply == REPLY, "the " .. context .. " runtime left " .. #tostring(reply) .. " bytes, not its reply")
end

test("rcu.table reads back a string whole", function()
	local t = rcu.table(4)
	for i, s in ipairs(values) do
		t[i] = s
	end
	for i, s in ipairs(values) do
		local read = t[i]
		assert(type(read) == "string" and read == s, "entry " .. i .. " read " .. #tostring(read) .. " bytes, not " .. #s)
	end
end)

test("rcu.table hands back a string that indexes a Lua table as its literal", function()
	local t = rcu.table(4)
	t.k = "key"
	local index = {}
	index[t.k] = true
	assert(index.key, "the string read indexed another slot than its literal")
end)

test("rcu.table keeps a string the writer no longer holds", function()
	local t = rcu.table(4)
	t.k = string.rep("y", LONG)
	collectgarbage()
	assert(t.k == string.rep("y", LONG), "the entry lost its string with the writer's")
end)

test("rcu.table hands back a string that outlives its entry", function()
	local t = rcu.table(4)
	t.k = string.rep("z", LONG)
	local read = t.k
	t.k = nil
	collectgarbage()
	assert(read == string.rep("z", LONG), "the string read lost its bytes with the entry")
end)

test("rcu.table replaces a string with every kind of value and back", function()
	local t = rcu.table(4)
	local sequence = {"one", "two", 2, "three", true, "four", data.new(8), "five"}
	for _, value in ipairs(sequence) do
		t.k = value
		assert(same(t.k, value), "a store of a " .. type(value) .. " read " .. tostring(t.k))
	end
	t.k = nil
	assert(t.k == nil, "a deleted string read " .. tostring(t.k))
end)

-- an IRQ runtime is armed past its body, which is the state a hook reads from; resume reaches it
test("rcu.table hands a string to an armed softirq runtime, which replaces it", function()
	cross("softirq")
end)

test("rcu.table hands a string to an armed hardirq runtime, which replaces it", function()
	cross("hardirq")
end)

lunatik._ENV[KEY] = nil

