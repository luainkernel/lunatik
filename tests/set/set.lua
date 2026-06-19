--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local set = require("set")
local test = require("util").test

test("set.new sorts unsorted input and has returns the tag", function()
	local s = set.new({["evil.com"] = 1, ["ads.net"] = 2, ["aaa.io"] = 4, ["zzz.net"] = 8})
	assert(s:has("aaa.io") == 4, "aaa.io tag")
	assert(s:has("zzz.net") == 8, "zzz.net tag")
	assert(s:has("evil.com") == 1, "evil.com tag")
	assert(s:has("nope") == 0, "absent returns 0")
	assert(#s == 4, "expected 4, got " .. #s)
end)

test("set:has is exact", function()
	local s = set.new({["a"] = 1, ["bb"] = 2, ["ccc"] = 4})
	assert(s:has("a") == 1 and s:has("bb") == 2 and s:has("ccc") == 4, "exact tags")
	assert(s:has("b") == 0, "b should not match")
	assert(s:has("cccc") == 0, "cccc should not match")
	assert(s:has("") == 0, "empty should not match")
end)

test("set:has distinguishes members that prefix one another", function()
	local s = set.new({["a"] = 8, ["ab"] = 1, ["abc"] = 2, ["abcd"] = 4})
	assert(s:has("a") == 8 and s:has("ab") == 1, "a, ab")
	assert(s:has("abc") == 2 and s:has("abcd") == 4, "abc, abcd")
	assert(s:has("abcde") == 0, "longer than any member is absent")
	assert(s:has("b") == 0, "b is absent")
end)

test("set:suffix unions the tags of every matching level", function()
	local s = set.new({["a.b.com"] = 1, ["b.com"] = 2, ["com"] = 4})
	assert(s:suffix("a.b.com", ".") == 7, "1|2|4 over all levels, got " .. tostring(s:suffix("a.b.com", ".")))
	assert(s:suffix("x.a.b.com", ".") == 7, "deeper still unions all three")
	assert(s:suffix("b.com", ".") == 6, "2|4")
	assert(s:suffix("com", ".") == 4, "just com")
	assert(s:suffix("nope.org", ".") == 0, "no match is 0")
end)

test("set:prefix unions the tags left-to-right", function()
	local s = set.new({["/usr/local"] = 1, ["/usr"] = 2})
	assert(s:prefix("/usr/local/bin", "/") == 3, "1|2 over /usr/local and /usr")
	assert(s:prefix("/usr/bin", "/") == 2, "only /usr")
	assert(s:prefix("/usr", "/") == 2, "exact /usr")
	assert(s:prefix("/var/log", "/") == 0, "no match is 0")
end)

test("a tag used as a bitmask is crossed on the Lua side", function()
	local ADS <const>, GAMBLING <const>, TRACKERS <const> = 1, 2, 4
	local cat = set.new({["evil.com"] = ADS | TRACKERS, ["com"] = GAMBLING})
	local block = ADS | GAMBLING
	-- x.evil.com unions evil.com (ads|trackers) with com (gambling)
	local m = cat:suffix("x.evil.com", ".")
	assert(m & block == block, "evil.com hits ads (own) and gambling (com)")
	assert(m & TRACKERS ~= 0, "and still carries trackers")
	assert(cat:suffix("casino.bet", ".") == 0, "casino.bet absent")
	assert(cat:suffix("foo.com", ".") & GAMBLING ~= 0, "any .com carries gambling")
end)

test("empty set", function()
	local s = set.new({})
	assert(#s == 0, "empty size")
	assert(s:has("anything") == 0, "empty has nothing")
	assert(s:suffix("a.b", ".") == 0, "empty suffix")
end)

test("a member may be the empty string", function()
	local s = set.new({[""] = 5})
	assert(s:has("") == 5, "empty-string member tag")
	assert(s:has("x") == 0, "x is not a member")
	assert(#s == 1, "expected 1, got " .. #s)
end)

test("tags across the 32-bit range round-trip", function()
	for _, tag in ipairs({1, 255, 256, 65535, 65536, 16777215, 4294967295}) do
		local s = set.new({["k"] = tag})
		assert(s:has("k") == tag, "tag " .. tag .. " round-trips, got " .. tostring(s:has("k")))
	end
end)

test("set:suffix rejects a multi-byte separator", function()
	local s = set.new({["a"] = 1})
	assert(not pcall(function() s:suffix("a.b", "..") end), "multi-byte sep should raise")
end)

test("set.new rejects a non-string member", function()
	assert(not pcall(function() set.new({[42] = 1, ["k"] = 2}) end), "non-string member should raise")
end)

test("set.new rejects a tag outside [1, 2^32)", function()
	assert(not pcall(function() set.new({["k"] = "not a number"}) end), "string tag should raise")
	assert(not pcall(function() set.new({["k"] = 0}) end), "tag 0 should raise")
	assert(not pcall(function() set.new({["k"] = -1}) end), "negative tag should raise")
	assert(not pcall(function() set.new({["k"] = 4294967296}) end), "tag >= 2^32 should raise")
end)

