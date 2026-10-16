--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local set = require("set")
local test = require("tests.lib").test

test("set.new sorts unsorted input", function()
	local s = set.new({"delta", "alpha", "charlie", "bravo"})
	assert(s:has("charlie"), "missing charlie")
	assert(s:has("bravo"), "missing bravo")
	assert(s:has("delta"), "missing delta")
	assert(not s:has("nope"), "false positive nope")
	assert(#s == 4, "expected 4, got " .. #s)
end)

test("set:has exact membership", function()
	local s = set.new({"a", "bb", "ccc"})
	assert(s:has("a") and s:has("bb") and s:has("ccc"), "missing exact member")
	assert(not s:has("b"), "b should not match")
	assert(not s:has("cccc"), "cccc should not match")
	assert(not s:has(""), "empty should not match")
end)

test("set keeps duplicates", function()
	local s = set.new({"x", "x", "y"})
	assert(s:has("x") and s:has("y"), "members present")
	assert(#s == 3, "duplicates kept, expected 3, got " .. #s)
end)

test("empty set", function()
	local s = set.new({})
	assert(#s == 0, "empty size")
	assert(not s:has("anything"), "empty has nothing")
end)

test("set with an empty-string member", function()
	local s = set.new({""})
	assert(s:has(""), "empty string is a member")
	assert(not s:has("x"), "x is not a member")
	assert(#s == 1, "expected 1, got " .. #s)
end)

test("set.new rejects a non-string member", function()
	assert(not pcall(function() set.new({"ok", 42}) end), "non-string member should raise")
end)

test("set.new rejects a map", function()
	local ok, err = pcall(set.new, {["a.b"] = 1})
	assert(not ok and err:find("not a sequence", 1, true), "expected the refusal, got " .. tostring(err))
end)

test("set.labeled match returns a member's labels", function()
	local s = set.labeled({["alpha"] = 1, ["bravo"] = 2, ["charlie"] = 4, ["delta"] = 8})
	assert(s:match("charlie") == 4, "charlie labels")
	assert(s:match("alpha") == 1, "alpha labels")
	assert(s:match("nope") == 0, "absent returns 0")
	assert(#s == 4, "expected 4, got " .. #s)
end)

test("set.labeled match unions the labels of every matching level", function()
	local s = set.labeled({["a.b.c"] = 1, ["b.c"] = 2, ["c"] = 4})
	assert(s:match("a.b.c") == 7, "1|2|4 over all levels, got " .. tostring(s:match("a.b.c")))
	assert(s:match("x.a.b.c") == 7, "deeper still unions all three")
	assert(s:match("b.c") == 6, "2|4")
	assert(s:match("c") == 4, "just c")
	assert(s:match("nope") == 0, "no match is 0")
end)

test("set.labeled match distinguishes members that suffix one another", function()
	local s = set.labeled({["c"] = 1, ["b.c"] = 2, ["a.b.c"] = 4})
	assert(s:match("c") == 1, "c")
	assert(s:match("b.c") == 3, "b.c unions b.c|c = 2|1")
	assert(s:match("a.b.c") == 7, "all three")
	assert(s:match("z.c") == 1, "z.c only c")
end)

test("a label is crossed as a bitmask on the Lua side", function()
	local RED <const>, GREEN <const>, BLUE <const> = 1, 2, 4
	local s = set.labeled({["a.b"] = RED | BLUE, ["b"] = GREEN})
	local want = RED | GREEN
	-- x.a.b unions a.b (red|blue) with b (green)
	local m = s:match("x.a.b")
	assert(m & want == want, "a.b carries red (own) and green (b)")
	assert(m & BLUE ~= 0, "and still carries blue")
	assert(s:match("z.w") == 0, "z.w absent")
	assert(s:match("c.b") & GREEN ~= 0, "any *.b carries green")
end)

test("empty labeled set", function()
	local s = set.labeled({})
	assert(#s == 0, "empty size")
	assert(s:match("a.b") == 0, "empty match")
end)

test("a labeled member may be the empty string, matched via a trailing separator", function()
	local s = set.labeled({[""] = 5})
	assert(s:match("a.") == 5, "trailing '.' reaches the empty-string member")
	assert(s:match("a") == 0, "no trailing '.', the empty string is not reached")
	assert(#s == 1, "expected 1, got " .. #s)
end)

test("labels across the 32-bit range round-trip", function()
	for _, label in ipairs({1, 255, 256, 65535, 65536, 16777215, 4294967295}) do
		local s = set.labeled({["k"] = label})
		assert(s:match("k") == label, "label " .. label .. " round-trips, got " .. tostring(s:match("k")))
	end
end)

test("set.labeled rejects a non-string member", function()
	assert(not pcall(function() set.labeled({[42] = 1, ["k"] = 2}) end), "non-string member should raise")
end)

test("set.labeled rejects a label outside [1, 2^32)", function()
	assert(not pcall(function() set.labeled({["k"] = "not a number"}) end), "string label should raise")
	assert(not pcall(function() set.labeled({["k"] = 0}) end), "label 0 should raise")
	assert(not pcall(function() set.labeled({["k"] = -1}) end), "negative label should raise")
	assert(not pcall(function() set.labeled({["k"] = 4294967296}) end), "label >= 2^32 should raise")
end)

test("set.labeled match refuses a plain set", function()
	local plain = set.new({}) -- empty, so a build without the refusal answers 0 rather than reading a label through NULL
	local ok, err = pcall(set.labeled({["a"] = 1}).match, plain, "a")
	assert(not ok and err:find("(set.labeled expected, got set)", 1, true), "expected the refusal, got " .. tostring(err))
end)

test("set.valued match returns the longest member's label alone", function()
	local s = set.valued({["c"] = 1, ["b.c"] = 2, ["a.b.c"] = 4})
	local label = s:match("a.b.c")
	assert(label == 4, "a.b.c itself, got " .. label)
	assert(s:match("x.a.b.c") == 4, "deeper still takes a.b.c")
	assert(s:match("b.c") == 2, "b.c, not b.c|c")
	assert(s:match("z.b.c") == 2, "z.b.c takes b.c")
	assert(s:match("z.c") == 1, "z.c takes c")
	assert(s:match("nope") == 0, "no match is 0")
	assert(#s == 3, "expected 3, got " .. #s)
end)

test("a label is a value in set.valued and a bitmask in set.labeled", function()
	local apps = {["go.com"] = 7, ["abcnews.go.com"] = 9}
	local valued, labeled = set.valued(apps), set.labeled(apps)
	assert(valued:match("www.abcnews.go.com") == 9, "abcnews.go.com decides alone")
	assert(valued:match("espn.go.com") == 7, "espn.go.com takes go.com")
	assert(labeled:match("www.abcnews.go.com") == 7 | 9, "set.labeled unions both levels")
end)

test("set.valued matches a member at a level, not inside one", function()
	local s = set.valued({["b.c"] = 2, ["ab.c"] = 1})
	local label = s:match("ab.c")
	assert(label == 1, "ab.c does not end in the level b.c, got " .. label)
	assert(s:match("x.b.c") == 2, "x.b.c ends in b.c")
end)

test("empty valued set", function()
	local s = set.valued({})
	assert(#s == 0, "empty size")
	assert(s:match("a.b") == 0, "empty match")
end)

test("a valued member may be the empty string, matched via a trailing separator", function()
	local s = set.valued({[""] = 1, ["a."] = 2})
	assert(s:match("x.a.") == 2, "a. is the longest member x.a. ends in")
	assert(s:match("b.") == 1, "trailing '.' reaches the empty-string member")
	assert(s:match("b") == 0, "no trailing '.', the empty string is not reached")
end)

test("set.valued labels across the 32-bit range round-trip", function()
	for _, label in ipairs({1, 65536, 4294967295}) do
		local s = set.valued({["k"] = label})
		assert(s:match("k") == label, "label " .. label .. " round-trips, got " .. s:match("k"))
	end
end)

test("set.valued rejects what set.labeled rejects", function()
	assert(not pcall(set.valued, {[42] = 1}), "non-string member should raise")
	assert(not pcall(set.valued, {["k"] = 0}), "label 0 should raise")
	assert(not pcall(set.valued, {["k"] = 4294967296}), "label >= 2^32 should raise")
end)

test("set.valued match refuses a set of another type", function()
	local valued, labeled = set.valued({["a"] = 1}), set.labeled({["a"] = 1})
	local ok, err = pcall(valued.match, set.new({}), "a")
	assert(not ok and err:find("(set.valued expected, got set)", 1, true), "expected the refusal, got " .. tostring(err))
	ok, err = pcall(valued.match, labeled, "a")
	assert(not ok and err:find("(set.valued expected, got set.labeled)", 1, true),
		"expected the refusal, got " .. tostring(err))
	ok, err = pcall(labeled.match, valued, "a")
	assert(not ok and err:find("(set.labeled expected, got set.valued)", 1, true),
		"expected the refusal, got " .. tostring(err))
end)

