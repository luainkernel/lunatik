--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local set = require("set")
local test = require("util").test

test("set.new sorts unsorted input", function()
	local s = set.new({"evil.com", "ads.net", "aaa.io", "zzz.net"})
	assert(s:has("aaa.io"), "missing aaa.io")
	assert(s:has("zzz.net"), "missing zzz.net")
	assert(s:has("evil.com"), "missing evil.com")
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

test("set.labeled match returns a member's flags", function()
	local s = set.labeled({["evil.com"] = 1, ["ads.net"] = 2, ["aaa.io"] = 4, ["zzz.net"] = 8})
	assert(s:match("aaa.io") == 4, "aaa.io flags")
	assert(s:match("evil.com") == 1, "evil.com flags")
	assert(s:match("nope.org") == 0, "absent returns 0")
	assert(#s == 4, "expected 4, got " .. #s)
end)

test("set.labeled match unions the flags of every matching level", function()
	local s = set.labeled({["a.b.com"] = 1, ["b.com"] = 2, ["com"] = 4})
	assert(s:match("a.b.com") == 7, "1|2|4 over all levels, got " .. tostring(s:match("a.b.com")))
	assert(s:match("x.a.b.com") == 7, "deeper still unions all three")
	assert(s:match("b.com") == 6, "2|4")
	assert(s:match("com") == 4, "just com")
	assert(s:match("nope.org") == 0, "no match is 0")
end)

test("set.labeled match distinguishes members that suffix one another", function()
	local s = set.labeled({["com"] = 1, ["b.com"] = 2, ["a.b.com"] = 4})
	assert(s:match("com") == 1, "com")
	assert(s:match("b.com") == 3, "b.com unions b.com|com = 2|1")
	assert(s:match("a.b.com") == 7, "all three")
	assert(s:match("z.com") == 1, "z.com only com")
end)

test("a labeled flag is crossed as a bitmask on the Lua side", function()
	local ADS <const>, GAMBLING <const>, TRACKERS <const> = 1, 2, 4
	local s = set.labeled({["evil.com"] = ADS | TRACKERS, ["com"] = GAMBLING})
	local block = ADS | GAMBLING
	-- x.evil.com unions evil.com (ads|trackers) with com (gambling)
	local m = s:match("x.evil.com")
	assert(m & block == block, "evil.com hits ads (own) and gambling (com)")
	assert(m & TRACKERS ~= 0, "and still carries trackers")
	assert(s:match("casino.bet") == 0, "casino.bet absent")
	assert(s:match("foo.com") & GAMBLING ~= 0, "any .com carries gambling")
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

test("labeled flags across the 32-bit range round-trip", function()
	for _, flag in ipairs({1, 255, 256, 65535, 65536, 16777215, 4294967295}) do
		local s = set.labeled({["k"] = flag})
		assert(s:match("k") == flag, "flag " .. flag .. " round-trips, got " .. tostring(s:match("k")))
	end
end)

test("set.labeled rejects a non-string member", function()
	assert(not pcall(function() set.labeled({[42] = 1, ["k"] = 2}) end), "non-string member should raise")
end)

test("set.labeled rejects a flag outside [1, 2^32)", function()
	assert(not pcall(function() set.labeled({["k"] = "not a number"}) end), "string flag should raise")
	assert(not pcall(function() set.labeled({["k"] = 0}) end), "flag 0 should raise")
	assert(not pcall(function() set.labeled({["k"] = -1}) end), "negative flag should raise")
	assert(not pcall(function() set.labeled({["k"] = 4294967296}) end), "flag >= 2^32 should raise")
end)

