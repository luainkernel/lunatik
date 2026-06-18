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

