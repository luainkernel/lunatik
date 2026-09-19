--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the language/identifiers test (see run.sh).
--

local test = require("util").test

local root <const> = "/lib/modules/lua/"

test("_VERSION names the kernel Lua", function()
	assert(_VERSION == "Lua 5.5-kernel", "_VERSION is " .. tostring(_VERSION))
end)

test("collectgarbage('count') answers in bytes", function()
	local count = collectgarbage("count")
	assert(count // 1 == count, "count is not an integer: " .. tostring(count))
	assert(count > 1024, "count reads as Kbytes: " .. tostring(count))
end)

test("package.path resolves under the module root", function()
	assert(package.path == root .. "?.lua;" .. root .. "?/init.lua", "package.path is " .. package.path)
end)

test("the entry points a module cannot have are absent", function()
	assert(os == nil, "os is present")
	assert(debug.debug == nil, "debug.debug is present")
end)

