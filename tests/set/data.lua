--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the set.fromdata test (see run.sh).

local lunatik = require("lunatik")
local data    = require("data")
local set     = require("set")
local test    = require("tests.lib").test
local check   = require("tests.set.check")

local pack, concat, insert, sort = string.pack, table.concat, table.insert, table.sort

local U32      <const> = 4
local RECEIVER <const> = "tests/set/data_recv"
local READONLY <const> = "read only"
local BOUNDS   <const> = "out of bounds"

local list = {"alpha", "bravo", "charlie", "delta"}
local map  = {["c"] = 1, ["b.c"] = 2, ["a.b.c"] = 4, ["k"] = 4294967295}

local same, raises = check.same, check.raises

-- where the u32 after the members begins
local function aligned(members)
	return (#concat(members) + U32 - 1) // U32 * U32
end

local LIST_AT   <const> = aligned(list)
local LIST_SIZE <const> = LIST_AT + U32 * (#list + 1)
local LIST_OFF2 <const> = #list[1] + #list[2]

local function sorted(labels)
	local members = {}
	for member in pairs(labels) do
		insert(members, member)
	end
	sort(members)
	return members
end

-- the members, their u32 offsets and their u32 labels, as set.fromdata reads them
local function arrays(members, labels)
	local offsets, values, pos = {pack("<I4", 0)}, {}, 0
	for _, member in ipairs(members) do
		pos = pos + #member
		insert(offsets, pack("<I4", pos))
		if labels then
			insert(values, pack("<I4", labels[member]))
		end
	end
	return concat(members), concat(offsets), concat(values)
end

-- a data holding the members first, then their offsets and their labels from at
local function place(members, labels, at, mode)
	local blob, offsets, values = arrays(members, labels)
	local d = data.new(at + #offsets + #values, mode)
	d:setstring(0, blob)
	d:setstring(at, offsets)
	d:setstring(at + #offsets, values)
	return d, {n = #members, offsets = at, labels = labels and at + #offsets or nil, blob = 0}
end

local function over(members, labels, mode)
	return place(members, labels, aligned(members), mode)
end

-- list over a data, its layout's fields replaced by fields, which set.fromdata refuses
local function refuses(fields)
	local d, layout = over(list)
	for field, value in pairs(fields) do
		layout[field] = value
	end
	raises(BOUNDS, set.fromdata, d, layout)
	return d
end

-- a set of list over a data whose offsets from i on are the ones given, which set.fromdata takes
local function corrupted(i, ...)
	local d, layout = over(list)
	for k, offset in ipairs({...}) do
		d:setstring(LIST_AT + U32 * (i + k - 1), pack("<I4", offset))
	end
	return set.fromdata(d, layout)
end

-- a set over a data no handle of the script holds
local function orphan()
	return set.fromdata(over(sorted(map), map))
end

test("set.fromdata answers what set.new answers over a table of the same members", function()
	same(set.fromdata(over(list)), set.new(list))
	same(set.fromdata(over(sorted(map), map)), set.new(map))
end)

test("set.fromdata of no members builds the empty set", function()
	local s = set.fromdata(over({}))
	assert(#s == 0 and not s:has("") and s:match("a.b") == 0, "the empty set answered")
end)

test("set.fromdata takes a single data", function()
	same(set.fromdata(over(list, nil, "single")), set.new(list))
end)

test("set.fromdata makes the data read only for good, and it keeps reading", function()
	local d, layout = over(list)
	local bytes = tostring(d)
	set.fromdata(d, layout)
	raises(READONLY, d.setbyte, d, 0, 0)
	raises(READONLY, d.setuint32, d, 0, 0)
	raises(READONLY, d.setstring, d, 0, "x")
	raises(READONLY, d.resize, d, #d + 1)
	assert(#d == #bytes and tostring(d) == bytes, "the data's bytes changed")
	assert(d:getstring(0, #list[1]) == list[1] and d:getuint32(LIST_AT) == 0, "the data's getters read otherwise")
	d:checksum()
end)

test("a layout set.fromdata refuses leaves the data read only", function()
	local d = refuses({offsets = LIST_SIZE - U32 * #list})
	raises(READONLY, d.setbyte, d, 0, 0)
end)

test("set.fromdata refuses a layout missing, or a field of it missing or outside the data", function()
	local d = over(list)
	raises("table expected", set.fromdata, d)
	d:setbyte(0, 0) -- still writable: a layout is read against the data only once it is a table
	raises("bad field 'n'", set.fromdata, over(list), {offsets = LIST_AT, blob = 0})
	refuses({blob = LIST_SIZE + 1})
	refuses({n = -1})
end)

test("set.fromdata refuses an array that does not fit in the data", function()
	refuses({offsets = LIST_SIZE - U32 * #list})
	refuses({labels = LIST_SIZE - U32 * (#list - 1)})
	refuses({n = #list + 1})
end)

test("set.fromdata refuses an array whose offset is not a multiple of 4", function()
	raises(BOUNDS, set.fromdata, place(list, nil, LIST_AT + 1))
	refuses({labels = LIST_AT + 1})
end)

test("set.fromdata reads no member its offsets put past the data or end before it starts", function()
	local past = corrupted(#list, LIST_SIZE + 1)
	assert(past:has(list[1]) and not past:has(list[#list]), "a member reaching past the data answered")
	local far = corrupted(#list - 1, 0x7ffffff0, 0x7ffffff5)
	assert(far:has(list[1]) and not far:has(list[#list]), "a member far past the data answered")
	local decreasing = corrupted(1, LIST_OFF2 + 1)
	assert(not decreasing:has(list[2]) and decreasing:match(list[2]) == 0, "a member ending before it starts answered")
end)

test("set.fromdata refuses an object other than a data, and a value other than a table or an object", function()
	raises("data expected", set.fromdata, set.new(list), {n = 0, offsets = 0, blob = 0})
	raises("invalid object", set.fromdata, "alpha", {n = 0, offsets = 0, blob = 0})
end)

test("set.new refuses a data, which only set.fromdata takes, at its first argument", function()
	raises("bad argument #1", set.new, over(list))
end)

test("a set over a data answers from another runtime once the data's handle is collected", function()
	local s = orphan()
	collectgarbage()
	lunatik.runtime(RECEIVER, "softirq"):resume(s)
end)

