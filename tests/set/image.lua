--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the set.image test (see run.sh).

local set   = require("set")
local image = require("set.image")
local test  = require("tests.lib").test
local check = require("tests.set.check")

local SCRATCH <const> = "/tmp/lunatik-set/"
local MAX     <const> = 4096

-- list.txt and map.txt in run.sh, as set.new takes them
local list = {"delta", "alpha", "charlie", "bravo", "alpha"}
local map  = {["c"] = 1, ["b.c"] = 2, ["a.b.c"] = 4, ["k"] = 4294967295}

-- the header, off[n+1] and the members of list.set, whose n is 4
local LIST_SIZE <const> = 16 + 4 * (4 + 1) + #"alphabravocharliedelta"

-- each copy run.sh broke at a rule of the header, and the rule set.image names for it
local broken = {
	{"magic", "not a set image"},
	{"short", "not a set image"},
	{"version", "unsupported version"},
	{"flags", "unknown flags"},
	{"truncated", "size mismatch"},
	{"trailing", "size mismatch"},
	{"count", "size mismatch"},
	{"length", "size mismatch"},
}

-- each copy run.sh broke at an offset, and what has answers for a and for b over it
local outside = {decreasing = {false, false}, past = {true, false}}

local same, raises = check.same, check.raises

local function path(name)
	return SCRATCH .. name .. ".set"
end

test("set.image.load of a list answers what set.new answers over the same members", function()
	same(image.load(path("list"), MAX), set.new(list))
end)

test("set.image.load of a map answers what set.new answers over the same members and labels", function()
	same(image.load(path("map"), MAX), set.new(map))
end)

test("set.image.load of an empty list or map builds the empty set", function()
	for _, name in ipairs({"empty", "emptymap"}) do
		local s = image.load(path(name), MAX)
		assert(#s == 0 and not s:has("") and s:match("a.b") == 0, name .. " answered")
	end
end)

test("set.image.load raises what data.load raises", function()
	assert(#image.load(path("list"), LIST_SIZE) == 4, "a file of maxbytes did not load")
	raises("EFBIG", image.load, path("list"), LIST_SIZE - 1)
	raises("ENOENT", image.load, path("missing"), MAX)
end)

test("set.image refuses a file that breaks a rule of the header, naming the rule", function()
	for _, case in ipairs(broken) do
		local name, rule = path(case[1]), case[2]
		raises(name .. ": " .. rule, image.load, name, MAX)
	end
end)

test("set.image reads no member whose offsets reach outside the file", function()
	for name, answers in pairs(outside) do
		local s = image.load(path(name), MAX)
		assert(s:has("a") == answers[1] and s:has("b") == answers[2], name .. " answered otherwise")
	end
end)

