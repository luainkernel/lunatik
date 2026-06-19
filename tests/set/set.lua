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

test("set:suffix matches by suffix after the separator", function()
	local s = set.new({"evil.com", "com"})
	assert(s:suffix("x.y.evil.com", "."), "subdomain of evil.com")
	assert(s:suffix("anything.com", "."), "any .com via com")
	assert(s:suffix("evil.com", "."), "exact evil.com")
	assert(not s:suffix("evil.org", "."), "evil.org not covered")
end)

test("set:prefix matches by prefix before the separator", function()
	local s = set.new({"/usr/local", "/etc"})
	assert(s:prefix("/usr/local/bin", "/"), "under /usr/local")
	assert(s:prefix("/etc/passwd", "/"), "under /etc")
	assert(not s:prefix("/usr", "/"), "/usr is not a member")
	assert(not s:prefix("/var/log", "/"), "/var/log not covered")
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
	assert(not s:suffix("a.b", "."), "empty suffix")
end)

test("set with an empty-string member", function()
	local s = set.new({""})
	assert(s:has(""), "empty string is a member")
	assert(not s:has("x"), "x is not a member")
	assert(#s == 1, "expected 1, got " .. #s)
end)

test("set:suffix rejects a multi-byte separator", function()
	local s = set.new({"a"})
	assert(not pcall(function() s:suffix("a.b", "..") end), "multi-byte sep should raise")
end)

test("set.new rejects a non-string member", function()
	assert(not pcall(function() set.new({"ok", 42}) end), "non-string member should raise")
end)

test("labeled set: has returns the label, nil when absent", function()
	local s = set.new({["evil.com"] = 7, ["ads.net"] = 3})
	assert(s:has("evil.com") == 7, "evil.com label")
	assert(s:has("ads.net") == 3, "ads.net label")
	assert(s:has("absent.com") == nil, "absent returns nil")
	assert(#s == 2, "expected 2, got " .. #s)
end)

test("labeled set: suffix and prefix return the matched label", function()
	local dom = set.new({["evil.com"] = 5, ["com"] = 1})
	assert(dom:suffix("x.y.evil.com", ".") == 5, "longest suffix wins")
	assert(dom:suffix("anything.com", ".") == 1, "falls back to com")
	assert(dom:suffix("evil.org", ".") == nil, "no match is nil")
	local path = set.new({["/usr/local"] = 9, ["/etc"] = 2})
	assert(path:prefix("/usr/local/bin", "/") == 9, "under /usr/local")
	assert(path:prefix("/var/log", "/") == nil, "no match is nil")
end)

test("labeled set: label 0 is present and distinct from nil", function()
	local s = set.new({["a"] = 0, ["b"] = 1})
	assert(s:has("a") == 0, "zero label is returned")
	assert(s:has("b") == 1, "one label")
	assert(s:has("c") == nil, "absent is nil")
end)

test("labeled set: width grows to hold the largest label", function()
	for _, label in ipairs({255, 256, 65535, 65536, 4294967296, 1 << 40}) do
		local s = set.new({["k"] = label, ["z"] = 0})
		assert(s:has("k") == label, "label " .. label .. " round-trips, got " .. tostring(s:has("k")))
	end
end)

test("labeled set: a bitmask of categories is crossed on the Lua side", function()
	local ADS <const>, GAMBLING <const>, TRACKERS <const> = 1, 2, 4
	local cat = set.new({
		["evil.com"]   = ADS | TRACKERS,
		["casino.bet"] = GAMBLING,
	})
	local block = ADS | GAMBLING
	assert(cat:suffix("x.evil.com", ".") & block ~= 0, "evil.com hits a blocked bit (ads)")
	assert(cat:suffix("casino.bet", ".") & block ~= 0, "casino.bet hits a blocked bit (gambling)")
	assert(cat:suffix("x.evil.com", ".") & TRACKERS ~= 0, "evil.com also carries the trackers bit")
end)

test("labeled set: empty map", function()
	local s = set.new({})
	assert(#s == 0, "empty size")
	assert(s:has("anything") == nil or s:has("anything") == false, "empty labeled lookup is falsy")
end)

test("set.new rejects a non-integer label", function()
	assert(not pcall(function() set.new({["k"] = "not a number"}) end), "string label should raise")
	assert(not pcall(function() set.new({["k"] = -1}) end), "negative label should raise")
end)

