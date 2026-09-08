--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the data bounds test (see run.sh).

local data = require("data")
local test = require("util").test

local PAGE    <const> = 4096
local MAXSIZE <const> = 0x7fffffff -- INT_MAX, the largest size data.new and data:resize serve
local MARK    <const> = 0x5a

local accepted <const> = {1, 8, PAGE, PAGE + 1, 1 << 20}
local refused  <const> = {0, -1, MAXSIZE + 1, math.maxinteger, math.mininteger}

local function refuses(what, f, ...)
	local ok, err = pcall(f, ...)
	assert(not ok, what .. " accepted a size it cannot serve")
	assert(err:match("out of bounds"), what .. " raised something else: " .. err)
end

test("data.new accepts a size it serves", function()
	for _, size in ipairs(accepted) do
		local d = data.new(size)
		assert(#d == size, "expected " .. size .. " bytes, got " .. #d)
		d:setbyte(size - 1, MARK)
		assert(d:getbyte(size - 1) == MARK, "the last byte of " .. size .. " did not survive")
	end
end)

test("data.new refuses a size it cannot serve", function()
	for _, size in ipairs(refused) do
		refuses("data.new", data.new, size)
	end
end)

test("data.new keeps taking a mode", function()
	assert(#data.new(8, "shared") == 8, "the shared mode lost the size")
	assert(#data.new(8, "single") == 8, "the single mode lost the size")
end)

test("data:resize accepts a size it serves", function()
	local d = data.new(8)
	d:setbyte(0, MARK)

	d:resize(PAGE * 2)
	assert(#d == PAGE * 2, "growing did not take, got " .. #d)
	assert(d:getbyte(0) == MARK, "growing lost the old bytes")

	d:resize(8)
	assert(#d == 8, "shrinking did not take, got " .. #d)
	assert(d:getbyte(0) == MARK, "shrinking lost the old bytes")
end)

test("data:resize refuses a size it cannot serve", function()
	local d = data.new(8)
	local resize = getmetatable(d).resize
	d:setbyte(0, MARK)
	for _, size in ipairs(refused) do
		refuses("data:resize", resize, d, size)
	end
	assert(#d == 8, "a refused resize changed the size to " .. #d)
	assert(d:getbyte(0) == MARK, "a refused resize dropped the buffer")
end)

