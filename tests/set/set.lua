--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local set = require("set")
local test = require("tests.lib").test

test("set.new sorts unsorted input and leaves the table as given", function()
	local members = {"delta", "alpha", "charlie", "bravo"}
	local s = set.new(members)
	assert(s:has("charlie"), "missing charlie")
	assert(s:has("bravo"), "missing bravo")
	assert(s:has("delta"), "missing delta")
	assert(not s:has("nope"), "false positive nope")
	assert(#s == 4, "expected 4, got " .. #s)
	assert(members[1] == "delta" and members[4] == "bravo", "the table was reordered")
end)

test("set:has exact membership", function()
	local s = set.new({"a", "bb", "ccc"})
	assert(s:has("a") and s:has("bb") and s:has("ccc"), "missing exact member")
	assert(not s:has("b"), "b should not match")
	assert(not s:has("cccc"), "cccc should not match")
	assert(not s:has(""), "empty should not match")
end)

test("a list's duplicates count once", function()
	local s = set.new({"x", "x", "y"})
	assert(s:has("x") and s:has("y"), "members present")
	assert(#s == 2, "expected 2, got " .. #s)
end)

test("empty set", function()
	local s = set.new({})
	assert(#s == 0, "empty size")
	assert(not s:has("anything"), "empty has nothing")
	assert(s:match("a.b") == 0, "empty match")
end)

test("set with an empty-string member", function()
	local s = set.new({""})
	assert(s:has(""), "empty string is a member")
	assert(not s:has("x"), "x is not a member")
	assert(#s == 1, "expected 1, got " .. #s)
end)

test("a list's match returns 1 for a member or a key below one", function()
	local s = set.new({"ads.com"})
	assert(s:match("ads.com") == 1, "the member itself")
	assert(s:match("x.ads.com") == 1, "a key below the member")
	assert(s:match("com") == 0, "a level above the member")
	assert(s:match("bads.com") == 0, "bads.com does not end in the level ads.com")
end)

test("a map's match returns the label of the longest member alone", function()
	local s = set.new({["c"] = 1, ["b.c"] = 2, ["a.b.c"] = 4})
	local label = s:match("a.b.c")
	assert(label == 4, "a.b.c itself, got " .. label)
	assert(s:match("x.a.b.c") == 4, "deeper still takes a.b.c")
	assert(s:match("b.c") == 2, "b.c, not b.c|c")
	assert(s:match("z.b.c") == 2, "z.b.c takes b.c")
	assert(s:match("z.c") == 1, "z.c takes c")
	assert(s:match("nope") == 0, "no match is 0")
	assert(#s == 3, "expected 3, got " .. #s)
end)

test("a map's match finds a member at a level, not inside one", function()
	local s = set.new({["b.c"] = 2, ["ab.c"] = 1})
	local label = s:match("ab.c")
	assert(label == 1, "ab.c does not end in the level b.c, got " .. label)
	assert(s:match("x.b.c") == 2, "x.b.c ends in b.c")
end)

test("a map's has tests exact membership", function()
	local s = set.new({["a.b"] = 3})
	assert(s:has("a.b"), "a.b is a member")
	assert(not s:has("b") and not s:has("x.a.b"), "a level or a key below is not a member")
end)

test("a map member may be the empty string, matched via a trailing separator", function()
	local s = set.new({[""] = 1, ["a."] = 2})
	assert(s:match("x.a.") == 2, "a. is the longest member x.a. ends in")
	assert(s:match("b.") == 1, "trailing '.' reaches the empty-string member")
	assert(s:match("b") == 0, "no trailing '.', the empty string is not reached")
end)

test("labels across the 32-bit range round-trip", function()
	for _, label in ipairs({1, 255, 256, 65535, 65536, 16777215, 4294967295}) do
		local s = set.new({["k"] = label})
		assert(s:match("k") == label, "label " .. label .. " round-trips, got " .. tostring(s:match("k")))
	end
end)

test("set.new rejects a non-string member", function()
	assert(not pcall(set.new, {"ok", 42}), "a list's non-string member should raise")
	assert(not pcall(set.new, {[42] = 1, ["k"] = 2}), "a map's non-string member should raise")
end)

test("set.new rejects a label outside [1, 2^32)", function()
	assert(not pcall(set.new, {["k"] = "not a number"}), "string label should raise")
	assert(not pcall(set.new, {["k"] = 0}), "label 0 should raise")
	assert(not pcall(set.new, {["k"] = -1}), "negative label should raise")
	assert(not pcall(set.new, {["k"] = 4294967296}), "label >= 2^32 should raise")
end)

test("set.new rejects a list and a map in one table", function()
	local ok, err = pcall(set.new, {"a", ["b"] = 1})
	assert(not ok and err:find("a list and a map mixed", 1, true), "expected the refusal, got " .. tostring(err))
end)

