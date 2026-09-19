--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the language/floats test (see run.sh).
--

local test = require("util").test

local unparsable <const> = {"return 1.5", "return 1e3", "return 0x1p4", "return 2 ^ 3", "return -1.5"}
local dropped <const> = {"sin", "cos", "tan", "asin", "acos", "atan", "exp", "log", "sqrt", "fmod",
	"modf", "floor", "ceil", "ldexp", "frexp", "deg", "rad", "random", "randomseed", "type", "pi", "huge"}
local kept <const> = {"abs", "tointeger", "ult", "max", "min", "maxinteger", "mininteger"}
local conversions <const> = {"%a", "%A", "%f", "%e", "%E", "%g", "%G"}

test("no float literal and no '^' reaches a chunk", function()
	for _, source in ipairs(unparsable) do
		assert(load(source) == nil, "compiled: " .. source)
	end
end)

test("'/' is integer division and dispatches __idiv", function()
	assert(1 / 2 == 0, "'/' is not integer division")
	local proxy = setmetatable({}, {__idiv = function() return "idiv" end})
	assert(proxy / 2 == "idiv", "'/' did not reach __idiv")
end)

test("math keeps its integer half and drops the rest", function()
	for _, name in ipairs(dropped) do
		assert(math[name] == nil, "math." .. name .. " is present")
	end
	for _, name in ipairs(kept) do
		assert(math[name] ~= nil, "math." .. name .. " is absent")
	end
end)

test("tonumber refuses a float and keeps an integer", function()
	assert(tonumber("1.5") == nil, "tonumber accepted a float")
	assert(tonumber("0x10") == 16, "tonumber lost hexadecimal")
end)

test("string.format refuses every float conversion", function()
	for _, conversion in ipairs(conversions) do
		assert(not pcall(string.format, conversion, 1), conversion .. " was accepted")
	end
end)

test("string.pack refuses the float options and packs 'n' as an integer", function()
	assert(#string.pack("n", 1) == #string.pack("j", 1), "'n' is not the integer option")
	assert(not pcall(string.pack, "f", 1), "'f' was accepted")
	assert(not pcall(string.pack, "d", 1), "'d' was accepted")
end)

