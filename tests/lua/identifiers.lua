--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the lua/identifiers test (see run.sh).
--

local test = require("util").test

local root <const> = "/lib/modules/lua/"
local streams <const> = {"stdin", "stdout", "stderr", "close", "flush", "input", "output", "popen", "read",
	"tmpfile", "write"}
local files <const> = {"lines", "open", "type"}
local missing <const> = "lunatik_no_such_module"

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

test("the registry is out of a script's reach", function()
	assert(debug.getregistry == nil, "debug.getregistry is present")
end)

test("io has no default stream, pipe or buffering control", function()
	for _, name in ipairs(streams) do
		assert(io[name] == nil, "io." .. name .. " is present")
	end
	for _, name in ipairs(files) do
		assert(io[name] ~= nil, "io." .. name .. " is absent")
	end
	local file <close> = assert(io.open("/proc/version"))
	assert(file.setvbuf == nil, "file:setvbuf is present")
	assert(not pcall(io.lines), "io.lines() read a default input")
end)

test("package has no cpath and resolves a C module in the kernel symbol table", function()
	assert(package.cpath == nil, "package.cpath is present")
	assert(#package.searchers == 3, "searchers are " .. #package.searchers)
	local ok, err = pcall(require, missing)
	assert(not ok and err:find("not found in kernel symbol table", 1, true), "require: " .. tostring(err))
end)

