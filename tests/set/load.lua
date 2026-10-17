--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the set.load test (see run.sh).
--

local lunatik = require("lunatik")
local set     = require("set")
local test    = require("tests.lib").test

local SCRATCH  <const> = "/tmp/lunatik-set/"
local MAX      <const> = 4096
local RECEIVER <const> = "tests/set/load_recv"
local REFUSAL  <const> = "not allowed once the runtime is armed"

-- list.txt and map.txt in run.sh, as set.new takes them
local list = {"delta", "alpha", "charlie", "bravo", "alpha"}
local map  = {["c"] = 1, ["b.c"] = 2, ["a.b.c"] = 4, ["k"] = 4294967295}

-- the header, off[n+1] and the members of list.set, whose n is 4
local LIST_SIZE <const> = 16 + 4 * (4 + 1) + #"alphabravocharliedelta"

local keys = {"alpha", "bravo", "charlie", "delta", "echo", "", "alph", "alphaa", "x.alpha", "alpha.",
	"a.b.c", "x.a.b.c", "b.c", "z.b.c", "z.c", "c", "k", "x.k", "ab.c", "nope"}

-- each copy run.sh broke, and the rule set.load names for it
local broken = {
	{"magic", "not a set file"},
	{"short", "not a set file"},
	{"version", "unsupported version"},
	{"flags", "unknown flags"},
	{"truncated", "size mismatch"},
	{"trailing", "size mismatch"},
	{"count", "size mismatch"},
	{"length", "size mismatch"},
	{"first", "offsets out of bounds"},
	{"last", "offsets out of bounds"},
	{"decreasing", "offsets out of order"},
	{"unsorted", "unsorted or repeated members"},
	{"repeated", "unsorted or repeated members"},
	{"unlabeled", "label outside [1, 2^32)"},
}

local function path(name)
	return SCRATCH .. name .. ".set"
end

local function same(loaded, built)
	assert(#loaded == #built, "loaded " .. #loaded .. " members, set.new built " .. #built)
	for _, key in ipairs(keys) do
		assert(loaded:has(key) == built:has(key), "has('" .. key .. "') differs")
		assert(loaded:match(key) == built:match(key),
			"match('" .. key .. "') is " .. loaded:match(key) .. ", set.new's " .. built:match(key))
	end
end

local function raises(expected, ...)
	local ok, err = pcall(set.load, ...)
	assert(not ok, "loaded what should raise " .. expected)
	assert(err:find(expected, 1, true), "raised '" .. tostring(err) .. "', not " .. expected)
end

local function resume(context)
	local runtime <close> = lunatik.runtime(RECEIVER, context)
	return pcall(runtime.resume, runtime)
end

local function refused(context)
	local ok, err = resume(context)
	assert(not ok, "an armed " .. context .. " runtime loaded a set")
	assert(err:match(REFUSAL), "an armed " .. context .. " runtime raised something else: " .. err)
end

test("set.load of a list answers what set.new answers over the same members", function()
	same(set.load(path("list"), MAX), set.new(list))
end)

test("set.load of a map answers what set.new answers over the same members and labels", function()
	same(set.load(path("map"), MAX), set.new(map))
end)

test("set.load of an empty list or map builds the empty set", function()
	for _, name in ipairs({"empty", "emptymap"}) do
		local s = set.load(path(name), MAX)
		assert(#s == 0, name .. " has " .. #s .. " members")
		assert(not s:has("") and s:match("a.b") == 0, name .. " answered")
	end
end)

test("set.load reads a file of maxbytes and raises EFBIG past it", function()
	assert(#set.load(path("list"), LIST_SIZE) == 4, "a file of maxbytes did not load")
	raises("EFBIG", path("list"), LIST_SIZE - 1)
end)

test("set.load raises the errno its read fails with", function()
	raises("ENOENT", path("missing"), MAX)
	raises("EINVAL", path("zero"), MAX)
	raises("EINVAL", SCRATCH .. "dir", MAX)
	raises("ETXTBSY", path("busy"), MAX)
end)

test("set.load refuses a maxbytes below 1", function()
	raises("out of bounds", path("list"), 0)
end)

test("set.load refuses a file that breaks a rule of the layout, naming the rule", function()
	for _, case in ipairs(broken) do
		local file, rule = path(case[1]), case[2]
		raises(file .. ": " .. rule, file, MAX)
	end
end)

test("set.load loads in a process runtime past its body", function()
	local ok, err = resume("process")
	assert(ok, err)
end)

-- an IRQ runtime is armed past its body, which is the state a hook calls from; resume reaches it
test("set.load refuses an armed softirq runtime", function()
	refused("softirq")
end)

test("set.load refuses an armed hardirq runtime", function()
	refused("hardirq")
end)

