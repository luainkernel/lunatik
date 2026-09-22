--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the lua/floats test (see run.sh).
--

local test = require("util").test

local floats <const> = {"1.5", "1e3", "0x1p4", ".5", "1."}
local pow <const> = "return 2 ^ 3"
local dropped <const> = {"sin", "cos", "tan", "asin", "acos", "atan", "exp", "log", "sqrt", "fmod",
	"modf", "floor", "ceil", "ldexp", "frexp", "deg", "rad", "random", "randomseed", "type", "pi", "huge"}
local kept <const> = {"abs", "tointeger", "ult", "max", "min", "maxinteger", "mininteger"}
local conversions <const> = {"%a", "%A", "%f", "%e", "%E", "%g", "%G"}

test("no float literal and no '^' reaches a chunk", function()
	for _, spelling in ipairs(floats) do
		assert(load("return " .. spelling) == nil, "compiled: " .. spelling)
	end
	assert(load(pow) == nil, "compiled: " .. pow)
end)

test("'/' is integer division and dispatches __idiv", function()
	local n = 1
	assert(1 / 2 == 0, "'/' is not integer division when folded")
	assert(n / 2 == 0, "'/' is not integer division on a register")
	assert("10" / 4 == 2, "'/' is not integer division on a coerced string")
	assert(not pcall(function() return n / 0 end), "'/' by zero did not raise")
	local proxy = setmetatable({}, {__idiv = function() return "idiv" end})
	assert(proxy / 2 == "idiv", "'/' did not reach __idiv")
end)

test("__div and __pow are not metamethods", function()
	local divisible = setmetatable({}, {__div = function() return "div" end})
	local ok, err = pcall(function() return divisible / 2 end)
	assert(not ok and err:find("perform arithmetic", 1, true), "'/' reached __div: " .. tostring(err))
	local metatable = getmetatable("")
	assert(metatable.__div == nil and metatable.__pow == nil, "string keeps __div or __pow")
end)

test("math keeps its integer half and drops the rest", function()
	for _, name in ipairs(dropped) do
		assert(math[name] == nil, "math." .. name .. " is present")
	end
	for _, name in ipairs(kept) do
		assert(math[name] ~= nil, "math." .. name .. " is absent")
	end
end)

test("tonumber refuses every float spelling and keeps an integer", function()
	for _, spelling in ipairs(floats) do
		assert(tonumber(spelling) == nil, "tonumber accepted " .. spelling)
	end
	assert(tonumber("0x10") == 16, "tonumber lost hexadecimal")
end)

test("string.format refuses every float conversion", function()
	for _, conversion in ipairs(conversions) do
		assert(not pcall(string.format, conversion, 1), conversion .. " was accepted")
	end
end)

test("string.pack refuses the float options and packs 'n' as an integer", function()
	assert(string.pack("n", 1) == string.pack("j", 1), "'n' is not the integer option")
	assert(string.unpack("n", string.pack("j", 7)) == 7, "'n' does not unpack as an integer")
	assert(not pcall(string.pack, "f", 1), "'f' was accepted")
	assert(not pcall(string.pack, "d", 1), "'d' was accepted")
end)

